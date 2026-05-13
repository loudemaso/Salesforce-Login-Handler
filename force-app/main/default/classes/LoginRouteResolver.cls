/**
 * Shared CMDT + marker permission set routing for SAML SSO URLs, used by {@code LoginRouterService} (Experience
 * Guest LWC). Pass {@code experienceBaseUrlOverride} when {@code Site.getBaseUrl()} in that context is not the
 * community root (e.g. pass {@code window.location.origin} from the LWC) so {@code Auth.AuthConfiguration.getSamlSsoUrl}
 * receives the Experience {@code my.site.com} host.
 */
public without sharing class LoginRouteResolver {
    private static final String LOG_PFX = 'LoginRouteResolver|';

    public static final String POST_LOGIN_START_URL = '/s/';
    public static final String ROUTE_SSO = 'SSO';
    public static final String ROUTE_PASSWORD = 'PASSWORD';
    public static final String ROUTE_NONE = 'NONE';

    public static final Integer MAX_IDENTIFIER_LENGTH = 255;
    private static final Integer DEBUG_URL_SNIP_LEN = 160;
    private static final Integer DEBUG_MARKER_JOIN_MAX = 400;

    /** Result of evaluating identifier-first routing for one org/user context. */
    public class DiscoverOutcome {
        public String routeType;
        public String redirectUrl;
        public String samlSettingApi;
        public Id matchedUserId;
    }

    /**
     * Resolves SSO vs password vs blocked for the given identifier (Email or Username shape).
     * matchedUserId is set when exactly one active user matches; samlSettingApi set when CMDT SAML row applied.
     */
    public static DiscoverOutcome resolveDiscover(String identifier) {
        return resolveDiscover(identifier, null);
    }

    /**
     * @param experienceBaseUrlOverride When non-blank, normalized with {@code normalizeExperienceBaseUrl} and used
     *         as the first argument to {@code getSamlSsoUrl} instead of {@code Site.getBaseUrl()} alone. Typical source:
     *         {@code window.location.origin} from {@code emailFirstLogin}.
     */
    public static DiscoverOutcome resolveDiscover(String identifier, String experienceBaseUrlOverride) {
        DiscoverOutcome o = new DiscoverOutcome();
        o.routeType = ROUTE_NONE;
        String experienceBaseEffective = normalizeExperienceBaseUrl(experienceBaseUrlOverride);

        logInfo(
            'resolveDiscover enter id=' +
                maskIdentifier(identifier) +
                ' experienceBaseEffective=' +
                summarizeUrlForLog(experienceBaseEffective) +
                ' siteGetBaseUrl=' +
                summarizeUrlForLog(Site.getBaseUrl()) +
                ' testCommunityOverride=' +
                (TEST_COMMUNITY_BASE_URL != null)
        );

        if (!isIdentifierPlausible(identifier)) {
            logInfo('resolveDiscover exit route=' + ROUTE_NONE + ' reason=implausibleIdentifier');
            return o;
        }
        List<User> users = findActiveUsersByLoginIdentifier(identifier.trim());
        if (users.size() != 1) {
            logInfo('resolveDiscover exit route=' + ROUTE_NONE + ' reason=userMatchCount=' + users.size());
            return o;
        }
        o.matchedUserId = users[0].Id;
        logDbg('resolveDiscover userId=' + o.matchedUserId + ' usernameLast3=' + lastChars(users[0].Username, 3));

        SsoBuildResult built = computeSsoUrlForUser(users[0].Id, experienceBaseEffective);
        if (built != null && String.isNotBlank(built.url)) {
            o.routeType = ROUTE_SSO;
            o.redirectUrl = built.url;
            o.samlSettingApi = built.samlApi;
            logInfo(
                'resolveDiscover exit route=' +
                    ROUTE_SSO +
                    ' samlSetting=' +
                    o.samlSettingApi +
                    ' redirectLen=' +
                    o.redirectUrl.length() +
                    ' redirectSnip=' +
                    snipForLog(o.redirectUrl)
            );
            return o;
        }
        Set<String> markerNames = loadPermissionSetNames(users[0].Id);
        logDbg('resolveDiscover markerNameCount=' + markerNames.size() + ' markers=' + joinMarkersForLog(markerNames));
        if (markerNames.isEmpty()) {
            o.routeType = ROUTE_PASSWORD;
            logInfo('resolveDiscover exit route=' + ROUTE_PASSWORD + ' reason=noPermissionSetMarkers');
            return o;
        }
        Client_Sso_Routing__mdt match = queryTopRoutingRow(markerNames);
        if (match == null || String.isBlank(match.Saml_Setting_Api_Name__c)) {
            o.routeType = ROUTE_PASSWORD;
            logInfo(
                'resolveDiscover exit route=' +
                    ROUTE_PASSWORD +
                    ' reason=noCmdtRowOrBlankSamlApi cmdtMatch=' +
                    (match != null)
            );
            return o;
        }
        o.samlSettingApi = match.Saml_Setting_Api_Name__c;
        System.debug(
            LoggingLevel.WARN,
            LOG_PFX +
                'samlSetting=' +
                o.samlSettingApi +
                ' ssoUrlBlank=true passwordFallback=true cmdtSamlSsoConfigIdSet=' +
                String.isNotBlank(match.Saml_Sso_Config_Id__c)
        );
        o.routeType = ROUTE_PASSWORD;
        logInfo('resolveDiscover exit route=' + ROUTE_PASSWORD + ' reason=ssoUrlBlankAfterCmdtMatch samlSetting=' + o.samlSettingApi);
        return o;
    }

    private class SsoBuildResult {
        String url;
        String samlApi;
    }

    private static SsoBuildResult computeSsoUrlForUser(Id userId, String experienceBaseUrlOverride) {
        Set<String> markerNames = loadPermissionSetNames(userId);
        if (markerNames.isEmpty()) {
            logDbg('computeSsoUrlForUser userId=' + userId + ' noMarkers');
            return null;
        }
        Client_Sso_Routing__mdt match = queryTopRoutingRow(markerNames);
        if (match == null || String.isBlank(match.Saml_Setting_Api_Name__c)) {
            logDbg(
                'computeSsoUrlForUser userId=' +
                    userId +
                    ' noCmdtMatchOrBlankSamlApi markers=' +
                    joinMarkersForLog(markerNames)
            );
            return null;
        }
        String samlApi = match.Saml_Setting_Api_Name__c;
        logDbg(
            'computeSsoUrlForUser userId=' +
                userId +
                ' cmdtDevName=' +
                match.DeveloperName +
                ' cmdtSamlApi=' +
                samlApi +
                ' cmdtHasSsoConfigIdText=' +
                String.isNotBlank(match.Saml_Sso_Config_Id__c)
        );
        String ssoUrl = buildSamlInitiationUrl(samlApi, match.Saml_Sso_Config_Id__c, experienceBaseUrlOverride);
        if (String.isBlank(ssoUrl)) {
            System.debug(
                LoggingLevel.WARN,
                LOG_PFX + 'samlSetting=' + samlApi + ' ssoUrlBlank=true passwordFallback=true (computeSsoUrlForUser)'
            );
            return null;
        }
        SsoBuildResult r = new SsoBuildResult();
        r.url = ssoUrl;
        r.samlApi = samlApi;
        logDbg('computeSsoUrlForUser ok samlSetting=' + samlApi + ' urlLen=' + ssoUrl.length());
        return r;
    }

    public static String maskIdentifier(String raw) {
        if (String.isBlank(raw) || !raw.contains('@')) {
            return '***';
        }
        String local = raw.substringBefore('@');
        String domain = raw.substringAfter('@');
        if (String.isBlank(domain)) {
            return '***';
        }
        String prefix = local.length() > 0 ? local.substring(0, 1) : '*';
        return prefix + '***@' + domain;
    }

    public static Boolean isIdentifierPlausible(String identifier) {
        if (String.isBlank(identifier)) {
            return false;
        }
        String trimmed = identifier.trim();
        if (trimmed.length() > MAX_IDENTIFIER_LENGTH) {
            return false;
        }
        if (!trimmed.contains('@') || trimmed.startsWith('@') || trimmed.endsWith('@')) {
            return false;
        }
        return true;
    }

    public static List<User> findActiveUsersByLoginIdentifier(String loginIdentifier) {
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
                SELECT DeveloperName, Saml_Setting_Api_Name__c, Saml_Sso_Config_Id__c
                FROM Client_Sso_Routing__mdt
                WHERE Is_Active__c = TRUE
                    AND Protocol__c = 'SAML'
                    AND Permission_Set_Name__c IN :permissionSetNames
                ORDER BY Priority__c DESC NULLS LAST
                LIMIT 1
            ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static String buildSamlInitiationUrl(
        String samlSettingDeveloperName,
        String optionalSamlSsoConfigIdText,
        String experienceBaseUrlOverride
    ) {
        if (TEST_SSO_URL_OVERRIDE != null) {
            logDbg('buildSamlInitiationUrl TEST_SSO_URL_OVERRIDE active; skipping platform getSamlSsoUrl');
            return TEST_SSO_URL_OVERRIDE;
        }
        Id samlConfigId = resolveSamlSsoConfigId(samlSettingDeveloperName, optionalSamlSsoConfigIdText);
        if (samlConfigId == null) {
            System.debug(
                LoggingLevel.WARN,
                LOG_PFX + 'buildSamlInitiationUrl no SamlSsoConfig id devName=' + samlSettingDeveloperName
            );
            return null;
        }
        String communityBase = communityBaseUrl(experienceBaseUrlOverride);
        if (String.isBlank(communityBase)) {
            System.debug(LoggingLevel.WARN, LOG_PFX + 'buildSamlInitiationUrl communityBaseBlank=true');
            return null;
        }
        logDbg(
            'buildSamlInitiationUrl call getSamlSsoUrl communityBase=' +
                communityBase +
                ' startUrl=' +
                POST_LOGIN_START_URL +
                ' samlConfigId=' +
                samlConfigId +
                ' samlDevName=' +
                samlSettingDeveloperName
        );
        try {
            String url = Auth.AuthConfiguration.getSamlSsoUrl(communityBase, POST_LOGIN_START_URL, String.valueOf(samlConfigId));
            logDbg(
                'buildSamlInitiationUrl getSamlSsoUrl result blank=' +
                    String.isBlank(url) +
                    ' len=' +
                    (url == null ? 0 : url.length()) +
                    ' snip=' +
                    snipForLog(url)
            );
            return url;
        } catch (Exception e) {
            System.debug(
                LoggingLevel.WARN,
                LOG_PFX +
                    'buildSamlInitiationUrl ex=' +
                    e.getTypeName() +
                    ' msg=' +
                    snipForLog(e.getMessage())
            );
            return null;
        }
    }

    private static Id resolveSamlSsoConfigId(String developerName, String optionalSamlSsoConfigIdText) {
        if (String.isNotBlank(optionalSamlSsoConfigIdText)) {
            try {
                Id fromCmdt = Id.valueOf(optionalSamlSsoConfigIdText.trim());
                logDbg('resolveSamlSsoConfigId source=CMDT_Saml_Sso_Config_Id__c id=' + fromCmdt);
                return fromCmdt;
            } catch (Exception e) {
                System.debug(LoggingLevel.WARN, LOG_PFX + 'resolveSamlSsoConfigId invalid Saml_Sso_Config_Id__c ex=' + e.getTypeName());
            }
        }
        List<SamlSsoConfig> rows = [
            SELECT Id FROM SamlSsoConfig WHERE DeveloperName = :developerName LIMIT 1
        ];
        if (rows.isEmpty()) {
            logDbg('resolveSamlSsoConfigId source=SOQL devName=' + developerName + ' rows=0');
            return null;
        }
        logDbg('resolveSamlSsoConfigId source=SOQL devName=' + developerName + ' id=' + rows[0].Id);
        return rows[0].Id;
    }

    /**
     * Trims a community or site URL to the root used for {@code Auth.AuthConfiguration.getSamlSsoUrl} (no trailing
     * slash; strips trailing {@code /login} and {@code /s/login}). Returns null when input is blank or normalizes to empty.
     */
    public static String normalizeExperienceBaseUrl(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        raw = raw.trim();
        while (raw.endsWith('/')) {
            raw = raw.substring(0, raw.length() - 1);
        }
        if (String.isBlank(raw)) {
            return null;
        }
        String lower = raw.toLowerCase();
        for (String trail : new List<String>{ '/s/login', '/login' }) {
            if (lower.endsWith(trail)) {
                raw = raw.substring(0, raw.length() - trail.length());
                while (raw.endsWith('/')) {
                    raw = raw.substring(0, raw.length() - 1);
                }
                lower = raw.toLowerCase();
            }
        }
        return String.isBlank(raw) ? null : raw;
    }

    private static String communityBaseUrl(String experienceBaseUrlOverride) {
        if (TEST_COMMUNITY_BASE_URL != null) {
            logDbg('communityBaseUrl using TEST_COMMUNITY_BASE_URL');
            return TEST_COMMUNITY_BASE_URL;
        }
        if (String.isNotBlank(experienceBaseUrlOverride)) {
            logDbg('communityBaseUrl source=experienceBaseUrlOverride value=' + summarizeUrlForLog(experienceBaseUrlOverride));
            return experienceBaseUrlOverride;
        }
        String base = Site.getBaseUrl();
        String out = String.isBlank(base) ? null : base.removeEnd('/');
        logDbg('communityBaseUrl source=Site.getBaseUrl value=' + summarizeUrlForLog(out));
        return out;
    }

    private static void logDbg(String msg) {
        System.debug(LoggingLevel.DEBUG, LOG_PFX + msg);
    }

    private static void logInfo(String msg) {
        System.debug(LoggingLevel.INFO, LOG_PFX + msg);
    }

    /** Short preview for logs; avoids dumping multi-kB URLs. */
    private static String snipForLog(String urlOrMsg) {
        if (String.isBlank(urlOrMsg)) {
            return '';
        }
        return urlOrMsg.length() <= DEBUG_URL_SNIP_LEN
            ? urlOrMsg
            : urlOrMsg.substring(0, DEBUG_URL_SNIP_LEN) + '…(len=' + urlOrMsg.length() + ')';
    }

    private static String summarizeUrlForLog(String url) {
        if (String.isBlank(url)) {
            return '(blank)';
        }
        return snipForLog(url);
    }

    private static String joinMarkersForLog(Set<String> markerNames) {
        if (markerNames == null || markerNames.isEmpty()) {
            return '';
        }
        List<String> sorted = new List<String>(markerNames);
        sorted.sort();
        String joined = String.join(sorted, ',');
        return joined.length() <= DEBUG_MARKER_JOIN_MAX
            ? joined
            : joined.substring(0, DEBUG_MARKER_JOIN_MAX) + '…(n=' + markerNames.size() + ')';
    }

    private static String lastChars(String s, Integer n) {
        if (String.isBlank(s) || n == null || n <= 0) {
            return '';
        }
        return s.length() <= n ? s : s.substring(s.length() - n);
    }

    @TestVisible private static List<Client_Sso_Routing__mdt> TEST_ROUTING_ROWS;
    @TestVisible private static String TEST_SSO_URL_OVERRIDE;
    @TestVisible private static String TEST_COMMUNITY_BASE_URL;
}
