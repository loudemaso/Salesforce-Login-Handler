/**
 * Email-first Experience Cloud login. The emailFirstLogin LWC calls discover() to route a visitor
 * by Username/Email to either a client SAML IdP (mapped via Client_Sso_Routing__mdt + a marker
 * permission set) or the password step on the same page, then calls passwordLogin() to sign in
 * via Site.login.
 *
 * Runs as Experience Guest; without sharing so user and permission-set lookups succeed regardless
 * of org-wide defaults.
 */
public without sharing class LoginRouter {

    public static final String ROUTE_SSO = 'SSO';
    public static final String ROUTE_PASSWORD = 'PASSWORD';
    public static final String ROUTE_NONE = 'NONE';

    private static final String POST_LOGIN_START_URL = '/s/';
    private static final Integer MAX_IDENTIFIER_LENGTH = 255;
    private static final String GENERIC_LOGIN_ERROR = 'Invalid username or password.';

    public class DiscoverResponse {
        @AuraEnabled public String route;
        @AuraEnabled public String redirectUrl;
    }

    public class LoginResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String redirectUrl;
        @AuraEnabled public String message;
    }

    /**
     * Routes the supplied identifier (Username or Email of an active site member) to SSO or the
     * password step.
     *
     * @param identifier        value the visitor typed on the email step.
     * @param communityBaseUrl  window.location.origin from the LWC; used as the first argument to
     *                          Auth.AuthConfiguration.getSamlSsoUrl. Falls back to Site.getBaseUrl()
     *                          when blank.
     */
    @AuraEnabled(cacheable = false)
    public static DiscoverResponse discover(String identifier, String communityBaseUrl) {
        DiscoverResponse response = new DiscoverResponse();
        response.route = ROUTE_NONE;

        if (!isIdentifierPlausible(identifier)) {
            return response;
        }
        List<User> users = findActiveUsersByIdentifier(identifier.trim());
        if (users.size() != 1) {
            return response;
        }
        Set<String> markers = loadMarkerPermissionSetNames(users[0].Id);
        if (markers.isEmpty()) {
            response.route = ROUTE_PASSWORD;
            return response;
        }
        Client_Sso_Routing__mdt row = findActiveSamlRoutingRow(markers);
        if (row == null || String.isBlank(row.Saml_Setting_Api_Name__c)) {
            response.route = ROUTE_PASSWORD;
            return response;
        }
        String url = buildSamlInitiationUrl(row.Saml_Setting_Api_Name__c, communityBaseUrl);
        if (String.isBlank(url)) {
            response.route = ROUTE_PASSWORD;
            return response;
        }
        response.route = ROUTE_SSO;
        response.redirectUrl = url;
        return response;
    }

    /**
     * Attempts a password sign-in for the unique active user matching the identifier. Returns a
     * generic message on any unsuccessful path so callers cannot distinguish unknown user from
     * wrong password.
     */
    @AuraEnabled(cacheable = false)
    public static LoginResult passwordLogin(String identifier, String password) {
        LoginResult result = attemptPasswordLogin(identifier, password);
        if (!result.success) {
            result.message = GENERIC_LOGIN_ERROR;
        }
        return result;
    }

    private static LoginResult attemptPasswordLogin(String identifier, String password) {
        LoginResult result = new LoginResult();
        result.success = false;

        if (!isIdentifierPlausible(identifier) || String.isBlank(password)) {
            return result;
        }
        List<User> users = findActiveUsersByIdentifier(identifier.trim());
        if (users.size() != 1 || String.isBlank(users[0].Username)) {
            return result;
        }
        PageReference redirect;
        try {
            redirect = Site.login(users[0].Username, password, POST_LOGIN_START_URL);
        } catch (Exception e) {
            return result;
        }
        String url = (redirect == null) ? null : redirect.getUrl();
        if (String.isBlank(url)) {
            return result;
        }
        result.success = true;
        result.redirectUrl = url;
        return result;
    }

    private static Boolean isIdentifierPlausible(String identifier) {
        if (String.isBlank(identifier)) {
            return false;
        }
        String trimmed = identifier.trim();
        if (trimmed.length() > MAX_IDENTIFIER_LENGTH) {
            return false;
        }
        return trimmed.contains('@') && !trimmed.startsWith('@') && !trimmed.endsWith('@');
    }

    private static List<User> findActiveUsersByIdentifier(String identifier) {
        return [
            SELECT Id, Username
            FROM User
            WHERE IsActive = TRUE AND (Username = :identifier OR Email = :identifier)
            LIMIT 2
        ];
    }

    private static Set<String> loadMarkerPermissionSetNames(Id userId) {
        Set<String> names = new Set<String>();
        for (PermissionSetAssignment psa : [
            SELECT PermissionSet.Name, PermissionSet.Label
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSet.IsOwnedByProfile = FALSE
        ]) {
            if (psa.PermissionSet == null) {
                continue;
            }
            if (String.isNotBlank(psa.PermissionSet.Name)) {
                names.add(psa.PermissionSet.Name);
            }
            if (String.isNotBlank(psa.PermissionSet.Label)) {
                names.add(psa.PermissionSet.Label);
            }
        }
        return names;
    }

    private static Client_Sso_Routing__mdt findActiveSamlRoutingRow(Set<String> permissionSetNames) {
        List<Client_Sso_Routing__mdt> rows = (TEST_ROUTING_ROWS != null)
            ? TEST_ROUTING_ROWS
            : [
                SELECT DeveloperName, Saml_Setting_Api_Name__c
                FROM Client_Sso_Routing__mdt
                WHERE Is_Active__c = TRUE
                    AND Permission_Set_Name__c IN :permissionSetNames
                LIMIT 1
            ];
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * Builds the SP-initiated SAML URL. Returns null when the SamlSsoConfig row cannot be located by
     * DeveloperName, the community base is missing, or the platform returns blank — callers treat
     * any null as a password fallback.
     */
    private static String buildSamlInitiationUrl(String samlSettingDeveloperName, String communityBaseUrl) {
        if (TEST_SSO_URL_OVERRIDE != null) {
            return TEST_SSO_URL_OVERRIDE;
        }
        List<SamlSsoConfig> configs = [
            SELECT Id FROM SamlSsoConfig WHERE DeveloperName = :samlSettingDeveloperName LIMIT 1
        ];
        if (configs.isEmpty()) {
            return null;
        }
        String communityBase = effectiveCommunityBase(communityBaseUrl);
        if (String.isBlank(communityBase)) {
            return null;
        }
        try {
            return Auth.AuthConfiguration.getSamlSsoUrl(
                communityBase,
                POST_LOGIN_START_URL,
                String.valueOf(configs[0].Id)
            );
        } catch (Exception e) {
            return null;
        }
    }

    private static String effectiveCommunityBase(String communityBaseUrl) {
        if (TEST_COMMUNITY_BASE_URL != null) {
            return TEST_COMMUNITY_BASE_URL;
        }
        String chosen = String.isNotBlank(communityBaseUrl) ? communityBaseUrl : Site.getBaseUrl();
        return String.isBlank(chosen) ? null : chosen.trim().removeEnd('/');
    }

    @TestVisible private static List<Client_Sso_Routing__mdt> TEST_ROUTING_ROWS;
    @TestVisible private static String TEST_SSO_URL_OVERRIDE;
    @TestVisible private static String TEST_COMMUNITY_BASE_URL;
}
