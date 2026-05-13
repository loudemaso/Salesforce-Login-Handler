/**
 * Email-first Experience Cloud login: SSO-vs-password discovery and password authentication via Site.login.
 *
 * Runs `without sharing` so the Experience Guest user can resolve User by Email. CRUD/FLS still apply to the
 * Guest profile/permission set — see the Login_Router_Guest permission set and README for setup details.
 *
 * Security: the post-auth landing path is server-pinned to `POST_LOGIN_START_URL` so the client cannot
 * influence where Site.login or the SAML round-trip returns to.
 */
public without sharing class LoginRouterService {
    private static final String POST_LOGIN_START_URL = '/s/';
    private static final Integer MAX_EMAIL_LENGTH = 255;
    private static final String ROUTE_SSO = 'SSO';
    private static final String ROUTE_PASSWORD = 'PASSWORD';
    private static final String GENERIC_LOGIN_ERROR = 'Invalid username or password.';

    public class DiscoverResult {
        @AuraEnabled public String correlationId;
        @AuraEnabled public String type;
        @AuraEnabled public String redirectUrl;
    }

    public class LoginResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String redirectUrl;
        @AuraEnabled public String message;
    }

    /**
     * Decides whether the email should be routed to a SAML IdP. Returns `type=SSO` with `redirectUrl` when CMDT
     * routes the user; otherwise returns `type=PASSWORD` with `redirectUrl=null`. Never reveals whether the
     * email exists in the org — all unmatched, ambiguous, error, and exception cases collapse to PASSWORD.
     */
    @AuraEnabled(cacheable = false)
    public static DiscoverResult discover(String email) {
        DiscoverResult out = new DiscoverResult();
        out.correlationId = newCorrelationId();
        out.type = ROUTE_PASSWORD;

        String samlApi = null;
        try {
            samlApi = resolveSsoRoute(email, out);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'LoginRouterService.discover corr=' + out.correlationId + ' ex=' + e.getTypeName());
        }
        logRouting(out.correlationId, email, out.type, samlApi);
        return out;
    }

    /**
     * Authenticates via `Site.login`. Returns `success=true` with `redirectUrl` on success; any failure
     * (bad credentials, locked, blank inputs, unexpected exception) returns `success=false` with the same
     * generic `message` so callers cannot distinguish failure reasons. Emits one INFO debug line per call.
     */
    @AuraEnabled(cacheable = false)
    public static LoginResult passwordLogin(String email, String password) {
        LoginResult lr = new LoginResult();
        lr.success = false;
        try {
            attemptPasswordLogin(email, password, lr);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'LoginRouterService.passwordLogin ex=' + e.getTypeName());
        }
        if (!lr.success) {
            lr.message = GENERIC_LOGIN_ERROR;
        }
        System.debug(
            LoggingLevel.INFO,
            'LoginRouterService.passwordLogin email=' + maskEmail(email) + ' success=' + lr.success
        );
        return lr;
    }

    // Mutates `lr` on success; returns silently on any failure so the caller can apply the uniform error.
    private static void attemptPasswordLogin(String email, String password, LoginResult lr) {
        if (!isEmailPlausible(email) || String.isBlank(password)) {
            return;
        }
        PageReference pr = Site.login(email.trim(), password, POST_LOGIN_START_URL);
        String url = (pr == null) ? null : pr.getUrl();
        if (String.isBlank(url)) {
            return;
        }
        lr.success = true;
        lr.redirectUrl = url;
    }

    // Mutates `out` to SSO when a SAML redirect URL is built; returns the SAML setting we considered
    // (used by the caller's single logRouting line) or null when no route applies.
    private static String resolveSsoRoute(String email, DiscoverResult out) {
        if (!isEmailPlausible(email)) {
            return null;
        }
        List<User> users = findActiveUsersByEmail(email.trim());
        if (users.size() != 1) {
            return null;
        }
        Set<String> markerNames = loadPermissionSetNames(users[0].Id);
        if (markerNames.isEmpty()) {
            return null;
        }
        Client_Sso_Routing__mdt match = queryTopRoutingRow(markerNames);
        if (match == null || String.isBlank(match.Saml_Setting_Api_Name__c)) {
            return null;
        }

        String samlApi = match.Saml_Setting_Api_Name__c;
        String ssoUrl = buildSamlInitiationUrl(samlApi);
        if (String.isNotBlank(ssoUrl)) {
            out.type = ROUTE_SSO;
            out.redirectUrl = ssoUrl;
        }
        return samlApi;
    }

    @TestVisible
    static String maskEmail(String email) {
        if (String.isBlank(email) || !email.contains('@')) {
            return '***';
        }
        String local = email.substringBefore('@');
        String domain = email.substringAfter('@');
        if (String.isBlank(domain)) {
            return '***';
        }
        String prefix = local.length() > 0 ? local.substring(0, 1) : '*';
        return prefix + '***@' + domain;
    }

    @TestVisible
    static Boolean isEmailPlausible(String email) {
        if (String.isBlank(email)) {
            return false;
        }
        String trimmed = email.trim();
        if (trimmed.length() > MAX_EMAIL_LENGTH) {
            return false;
        }
        if (!trimmed.contains('@') || trimmed.startsWith('@') || trimmed.endsWith('@')) {
            return false;
        }
        return true;
    }

    private static List<User> findActiveUsersByEmail(String email) {
        return [
            SELECT Id
            FROM User
            WHERE Email = :email AND IsActive = TRUE
            LIMIT 2
        ];
    }

    private static Set<String> loadPermissionSetNames(Id userId) {
        Set<String> names = new Set<String>();
        for (PermissionSetAssignment psa : [
            SELECT PermissionSet.Name
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSet.IsOwnedByProfile = FALSE
        ]) {
            if (psa.PermissionSet != null && String.isNotBlank(psa.PermissionSet.Name)) {
                names.add(psa.PermissionSet.Name);
            }
        }
        return names;
    }

    private static Client_Sso_Routing__mdt queryTopRoutingRow(Set<String> permissionSetNames) {
        List<Client_Sso_Routing__mdt> rows = (TEST_ROUTING_ROWS != null)
            ? TEST_ROUTING_ROWS
            : [
                SELECT Saml_Setting_Api_Name__c
                FROM Client_Sso_Routing__mdt
                WHERE Is_Active__c = TRUE
                    AND Protocol__c = 'SAML'
                    AND Permission_Set_Name__c IN :permissionSetNames
                ORDER BY Priority__c DESC NULLS LAST
                LIMIT 1
            ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static String buildSamlInitiationUrl(String samlSettingDeveloperName) {
        if (TEST_SSO_URL_OVERRIDE != null) {
            return TEST_SSO_URL_OVERRIDE;
        }
        Id samlConfigId = resolveSamlSsoConfigId(samlSettingDeveloperName);
        if (samlConfigId == null) {
            return null;
        }
        String communityBase = communityBaseUrl();
        if (String.isBlank(communityBase)) {
            return null;
        }
        try {
            return Auth.AuthConfiguration.getSamlSsoUrl(communityBase, POST_LOGIN_START_URL, String.valueOf(samlConfigId));
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'LoginRouterService.buildSamlInitiationUrl ex=' + e.getTypeName());
            return null;
        }
    }

    private static Id resolveSamlSsoConfigId(String developerName) {
        List<SamlSsoConfig> rows = [
            SELECT Id FROM SamlSsoConfig WHERE DeveloperName = :developerName LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Id;
    }

    private static String communityBaseUrl() {
        if (TEST_COMMUNITY_BASE_URL != null) {
            return TEST_COMMUNITY_BASE_URL;
        }
        String base = Site.getBaseUrl();
        return String.isBlank(base) ? null : base.removeEnd('/');
    }

    private static void logRouting(String correlationId, String rawEmail, String routeType, String samlSettingApi) {
        String samlPart = String.isBlank(samlSettingApi) ? '' : (' samlSetting=' + samlSettingApi);
        System.debug(
            LoggingLevel.INFO,
            'LoginRouterService corr=' + correlationId + ' email=' + maskEmail(rawEmail) + ' route=' + routeType + samlPart
        );
    }

    // 16 random bytes formatted as 8-4-4-4-12 hex. Used only as a log correlation id — not a standards-compliant UUIDv4.
    private static String newCorrelationId() {
        String h = EncodingUtil.convertToHex(Crypto.generateAesKey(128));
        return h.substring(0, 8) + '-' + h.substring(8, 12) + '-' + h.substring(12, 16) + '-' + h.substring(16, 20) + '-' + h.substring(20, 32);
    }

    // ------------------------------------------------------------------------
    // Test seams. Production code leaves these null and follows the live path;
    // tests assign overrides to exercise SOQL/CMDT/SAML branches that are not
    // addressable from @IsTest (Custom Metadata routing rows, SamlSsoConfig,
    // and Site.getBaseUrl).
    // ------------------------------------------------------------------------
    @TestVisible private static List<Client_Sso_Routing__mdt> TEST_ROUTING_ROWS;
    @TestVisible private static String TEST_SSO_URL_OVERRIDE;
    @TestVisible private static String TEST_COMMUNITY_BASE_URL;
}
