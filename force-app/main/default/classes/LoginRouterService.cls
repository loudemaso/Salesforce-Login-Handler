/**
 * Email-first Experience Cloud login: discover routing (SSO vs password) and password login via Site.login.
 * Runs without sharing so the Experience Guest user can resolve User by Email; CRUD/FLS still apply to Guest.
 */
public without sharing class LoginRouterService {
    private static final Integer MAX_EMAIL_LENGTH = 255;
    private static final String ROUTE_SSO = 'SSO';
    private static final String ROUTE_PASSWORD = 'PASSWORD';
    private static final String GENERIC_LOGIN_ERROR = 'Invalid username or password.';

    public class DiscoverResult {
        @AuraEnabled
        public String correlationId;
        @AuraEnabled
        public String type;
        @AuraEnabled
        public String redirectUrl;
        @AuraEnabled
        public String normalizedStartUrl;
    }

    public class LoginResult {
        @AuraEnabled
        public Boolean success;
        @AuraEnabled
        public String redirectUrl;
        @AuraEnabled
        public String message;
    }

    @AuraEnabled(cacheable = false)
    public static DiscoverResult discover(String email, String startUrl) {
        String correlationId = newUuid();
        String normalizedStart = normalizeStartUrl(startUrl);
        DiscoverResult out = new DiscoverResult();
        out.correlationId = correlationId;
        out.normalizedStartUrl = normalizedStart;
        out.type = ROUTE_PASSWORD;
        out.redirectUrl = null;

        try {
            if (!isEmailPlausible(email)) {
                logRouting(correlationId, maskEmail(email), ROUTE_PASSWORD, null);
                return out;
            }

            List<User> users = findActiveUsersByEmail(email.trim());
            if (users.isEmpty() || users.size() > 1) {
                logRouting(correlationId, maskEmail(email), ROUTE_PASSWORD, null);
                return out;
            }

            User u = users[0];
            Set<String> markerNames = loadPermissionSetNames(u.Id);
            if (markerNames.isEmpty()) {
                logRouting(correlationId, maskEmail(email), ROUTE_PASSWORD, null);
                return out;
            }

            Client_Sso_Routing__mdt match = queryTopRoutingRow(markerNames);
            if (match == null || String.isBlank(match.Saml_Setting_Api_Name__c)) {
                logRouting(correlationId, maskEmail(email), ROUTE_PASSWORD, null);
                return out;
            }

            String ssoUrl = buildSamlInitiationUrl(normalizedStart, match.Saml_Setting_Api_Name__c);
            if (String.isBlank(ssoUrl)) {
                logRouting(correlationId, maskEmail(email), ROUTE_PASSWORD, match.Saml_Setting_Api_Name__c);
                return out;
            }

            out.type = ROUTE_SSO;
            out.redirectUrl = ssoUrl;
            logRouting(correlationId, maskEmail(email), ROUTE_SSO, match.Saml_Setting_Api_Name__c);
            return out;
        } catch (Exception e) {
            logRouting(correlationId, maskEmail(email), ROUTE_PASSWORD, null);
            return out;
        }
    }

    @AuraEnabled(cacheable = false)
    public static LoginResult passwordLogin(String email, String password, String startUrl) {
        LoginResult lr = new LoginResult();
        lr.success = false;
        lr.redirectUrl = null;
        lr.message = null;

        if (!isEmailPlausible(email) || String.isBlank(password)) {
            lr.message = GENERIC_LOGIN_ERROR;
            return lr;
        }

        String normalizedStart = normalizeStartUrl(startUrl);
        String identifier = email.trim();

        try {
            PageReference pr = Site.login(identifier, password, normalizedStart);
            if (pr == null) {
                lr.message = GENERIC_LOGIN_ERROR;
                return lr;
            }
            String url = pr.getUrl();
            if (String.isBlank(url)) {
                lr.message = GENERIC_LOGIN_ERROR;
                return lr;
            }
            lr.success = true;
            lr.redirectUrl = url;
            return lr;
        } catch (Exception e) {
            lr.message = GENERIC_LOGIN_ERROR;
            return lr;
        }
    }

    @TestVisible
    static String normalizeStartUrl(String raw) {
        return '/s/';
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
        if (!trimmed.contains('@')) {
            return false;
        }
        if (trimmed.startsWith('@') || trimmed.endsWith('@')) {
            return false;
        }
        return true;
    }

    private static List<User> findActiveUsersByEmail(String email) {
        return [
            SELECT Id, Username, Email, IsActive
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
        List<Client_Sso_Routing__mdt> rows = [
            SELECT Permission_Set_Name__c, Protocol__c, Saml_Setting_Api_Name__c, Priority__c, Is_Active__c
            FROM Client_Sso_Routing__mdt
            WHERE
                Is_Active__c = TRUE
                AND Protocol__c = 'SAML'
                AND Permission_Set_Name__c IN :permissionSetNames
            ORDER BY Priority__c DESC NULLS LAST
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * Builds SAML IdP redirect using platform API when available.
     */
    private static String buildSamlInitiationUrl(String startUrlRelative, String samlSettingDeveloperName) {
        if (String.isBlank(samlSettingDeveloperName)) {
            return null;
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
            return Auth.AuthConfiguration.getSamlSsoUrl(
                communityBase,
                startUrlRelative,
                String.valueOf(samlConfigId)
            );
        } catch (Exception e) {
            return null;
        }
    }

    private static Id resolveSamlSsoConfigId(String developerName) {
        List<SamlSsoConfig> rows = [
            SELECT Id
            FROM SamlSsoConfig
            WHERE DeveloperName = :developerName
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0].Id;
    }

    private static String communityBaseUrl() {
        if (Test.isRunningTest()) {
            return 'https://example.test.my.site.com';
        }
        String base = Site.getBaseUrl();
        if (String.isBlank(base)) {
            return null;
        }
        return base.removeEnd('/');
    }

    private static void logRouting(String correlationId, String maskedEmail, String routeType, String samlSettingApi) {
        String samlPart = String.isBlank(samlSettingApi) ? '' : (' samlSetting=' + samlSettingApi);
        System.debug(
            LoggingLevel.INFO,
            'LoginRouterService corr=' + correlationId + ' email=' + maskedEmail + ' route=' + routeType + samlPart
        );
    }

    private static String newUuid() {
        Blob b = Crypto.generateAesKey(128);
        String h = EncodingUtil.convertToHex(b);
        return h.substring(0, 8) + '-' + h.substring(8, 12) + '-' + h.substring(12, 16) + '-' + h.substring(16, 20) + '-' + h.substring(20, 32);
    }
}
