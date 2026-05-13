/**
 * Email-first Experience Cloud login: SSO-vs-password discovery and password authentication via Site.login.
 *
 * Runs `without sharing` so the Experience Guest user can resolve User by Email or Username. CRUD/FLS still apply to the
 * Guest profile/permission set — see the Login_Router_Guest permission set and README for setup details.
 *
 * Security: the post-auth landing path is server-pinned to `POST_LOGIN_START_URL` so the client cannot
 * influence where Site.login or the SAML round-trip returns to.
 */
public without sharing class LoginRouterService {
    private static final String POST_LOGIN_START_URL = '/s/';
    private static final Integer MAX_EMAIL_LENGTH = 255;
    private static final String ROUTE_SSO = 'SSO';
    /** Exactly one active user matched and they have no applicable SSO routing — client may show the password step. */
    private static final String ROUTE_PASSWORD = 'PASSWORD';
    /** Do not show password: ambiguous/unknown identifier, implausible input, or unexpected error (SSO URL blank falls back to PASSWORD when CMDT matched). */
    private static final String ROUTE_NONE = 'NONE';
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
     * Resolves the login identifier (Email or Username): returns `type=SSO` with `redirectUrl` when CMDT routes to a
     * working SAML URL; `type=PASSWORD` when exactly one active user matches and either they have no applicable SSO
     * CMDT row or the SAML initiation URL cannot be built (misconfiguration — password offered so the member is not
     * stranded; fix SAML for production); `type=NONE` when the client must stay on the identifier step (no match,
     * multiple matches, implausible input, or exception). Never reveals whether the identifier exists for unknown vs
     * ambiguous cases — those collapse to `NONE`.
     */
    @AuraEnabled(cacheable = false)
    public static DiscoverResult discover(String email) {
        DiscoverResult out = new DiscoverResult();
        out.correlationId = newCorrelationId();
        out.type = ROUTE_NONE;

        String samlApi = null;
        try {
            samlApi = applyDiscoverRouting(email, out);
        } catch (Exception e) {
            out.type = ROUTE_NONE;
            System.debug(LoggingLevel.WARN, 'LoginRouterService.discover corr=' + out.correlationId + ' ex=' + e.getTypeName());
        }
        logRouting(out.correlationId, email, out.type, samlApi);
        return out;
    }

    /**
     * Authenticates via `Site.login` with the matched user's Username (input may equal User.Email or User.Username).
     * Returns success=true with redirectUrl on success; any failure (bad credentials, locked, blank inputs,
     * unexpected exception) returns success=false with the same generic message so callers cannot distinguish
     * failure reasons. Emits one INFO debug line per call.
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
        String loginId = email.trim();
        List<User> users = findActiveUsersByLoginIdentifier(loginId);
        if (users.size() != 1 || String.isBlank(users[0].Username)) {
            return;
        }
        PageReference pr = Site.login(users[0].Username, password, POST_LOGIN_START_URL);
        String url = (pr == null) ? null : pr.getUrl();
        if (String.isBlank(url)) {
            return;
        }
        lr.success = true;
        lr.redirectUrl = url;
    }

    /**
     * Mutates `out.type` / `out.redirectUrl`. Returns SAML setting API name for logging when a CMDT SAML row applied
     * (whether or not the SSO URL succeeded); otherwise null.
     */
    private static String applyDiscoverRouting(String email, DiscoverResult out) {
        if (!isEmailPlausible(email)) {
            out.type = ROUTE_NONE;
            return null;
        }
        List<User> users = findActiveUsersByLoginIdentifier(email.trim());
        if (users.size() != 1) {
            out.type = ROUTE_NONE;
            return null;
        }

        Set<String> markerNames = loadPermissionSetNames(users[0].Id);
        if (markerNames.isEmpty()) {
            out.type = ROUTE_PASSWORD;
            return null;
        }
        Client_Sso_Routing__mdt match = queryTopRoutingRow(markerNames);
        if (match == null || String.isBlank(match.Saml_Setting_Api_Name__c)) {
            out.type = ROUTE_PASSWORD;
            return null;
        }

        String samlApi = match.Saml_Setting_Api_Name__c;
        String ssoUrl = buildSamlInitiationUrl(samlApi, match.Saml_Sso_Config_Id__c);
        if (String.isNotBlank(ssoUrl)) {
            out.type = ROUTE_SSO;
            out.redirectUrl = ssoUrl;
            return samlApi;
        }
        // CMDT maps this user to SAML but initiation URL is blank (misconfigured SAML, base URL, etc.).
        // Still require exactly one user; offer password so the member is not stranded — fix SAML/CMDT for strict SSO-only.
        System.debug(
            LoggingLevel.WARN,
            'LoginRouterService.applyDiscoverRouting samlSetting=' + samlApi + ' ssoUrlBlank=true passwordFallback=true'
        );
        out.type = ROUTE_PASSWORD;
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

    /** One row when the identifier uniquely matches an active user’s Username or Email; otherwise zero or two-plus. */
    private static List<User> findActiveUsersByLoginIdentifier(String loginIdentifier) {
        return [
            SELECT Id, Username
            FROM User
            WHERE IsActive = TRUE AND (Username = :loginIdentifier OR Email = :loginIdentifier)
            LIMIT 2
        ];
    }

    private static Set<String> loadPermissionSetNames(Id userId) {
        Set<String> names = new Set<String>();
        for (PermissionSetAssignment psa : [
            SELECT PermissionSet.Name, PermissionSet.Label
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSet.IsOwnedByProfile = FALSE
        ]) {
            if (psa.PermissionSet != null) {
                if (String.isNotBlank(psa.PermissionSet.Name)) {
                    names.add(psa.PermissionSet.Name);
                }
                if (String.isNotBlank(psa.PermissionSet.Label)) {
                    names.add(psa.PermissionSet.Label);
                }
            }
        }
        return names;
    }

    private static Client_Sso_Routing__mdt queryTopRoutingRow(Set<String> permissionSetNames) {
        List<Client_Sso_Routing__mdt> rows = (TEST_ROUTING_ROWS != null)
            ? TEST_ROUTING_ROWS
            : [
                SELECT Saml_Setting_Api_Name__c, Saml_Sso_Config_Id__c
                FROM Client_Sso_Routing__mdt
                WHERE Is_Active__c = TRUE
                    AND Protocol__c = 'SAML'
                    AND Permission_Set_Name__c IN :permissionSetNames
                ORDER BY Priority__c DESC NULLS LAST
                LIMIT 1
            ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static String buildSamlInitiationUrl(String samlSettingDeveloperName, String optionalSamlSsoConfigIdText) {
        if (TEST_SSO_URL_OVERRIDE != null) {
            return TEST_SSO_URL_OVERRIDE;
        }
        Id samlConfigId = resolveSamlSsoConfigId(samlSettingDeveloperName, optionalSamlSsoConfigIdText);
        if (samlConfigId == null) {
            System.debug(
                LoggingLevel.WARN,
                'LoginRouterService.buildSamlInitiationUrl no SamlSsoConfig id devName=' + samlSettingDeveloperName
            );
            return null;
        }
        String communityBase = communityBaseUrl();
        if (String.isBlank(communityBase)) {
            System.debug(LoggingLevel.WARN, 'LoginRouterService.buildSamlInitiationUrl communityBaseBlank=true');
            return null;
        }
        try {
            return Auth.AuthConfiguration.getSamlSsoUrl(communityBase, POST_LOGIN_START_URL, String.valueOf(samlConfigId));
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'LoginRouterService.buildSamlInitiationUrl ex=' + e.getTypeName());
            return null;
        }
    }

    /** Prefers CMDT Id (Guest-safe); otherwise queries SamlSsoConfig by DeveloperName (often fails for Guest). */
    private static Id resolveSamlSsoConfigId(String developerName, String optionalSamlSsoConfigIdText) {
        if (String.isNotBlank(optionalSamlSsoConfigIdText)) {
            try {
                return Id.valueOf(optionalSamlSsoConfigIdText.trim());
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, 'LoginRouterService.resolveSamlSsoConfigId invalid Saml_Sso_Config_Id__c');
            }
        }
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
