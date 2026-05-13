/**
 * Experience Guest entrypoints for {@code emailFirstLogin}: {@code discover} (identifier routing + SAML URL) and
 * {@code passwordLogin} via {@code Site.login}.
 */
public without sharing class LoginRouterService {
    private static final String LOG_PFX = 'LoginRouterService|';

    private static final String ROUTE_SSO = LoginRouteResolver.ROUTE_SSO;
    private static final String ROUTE_PASSWORD = LoginRouteResolver.ROUTE_PASSWORD;
    private static final String ROUTE_NONE = LoginRouteResolver.ROUTE_NONE;
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

    @AuraEnabled(cacheable = false)
    public static DiscoverResult discover(String email, String communityBaseUrl) {
        DiscoverResult out = new DiscoverResult();
        out.correlationId = newCorrelationId();
        out.type = ROUTE_NONE;

        String normalizedBase = LoginRouteResolver.normalizeExperienceBaseUrl(communityBaseUrl);
        System.debug(
            LoggingLevel.DEBUG,
            LOG_PFX +
                'discover enter corr=' +
                out.correlationId +
                ' id=' +
                LoginRouteResolver.maskIdentifier(email) +
                ' communityBaseRaw=' +
                summarize(communityBaseUrl) +
                ' communityBaseNorm=' +
                summarize(normalizedBase) +
                ' siteGetBaseUrl=' +
                summarize(Site.getBaseUrl())
        );

        String samlApi = null;
        try {
            LoginRouteResolver.DiscoverOutcome resolved = LoginRouteResolver.resolveDiscover(email, normalizedBase);
            out.type = resolved.routeType;
            out.redirectUrl = resolved.redirectUrl;
            samlApi = resolved.samlSettingApi;
            System.debug(
                LoggingLevel.DEBUG,
                LOG_PFX +
                    'discover resolved corr=' +
                    out.correlationId +
                    ' route=' +
                    out.type +
                    ' redirectLen=' +
                    (String.isBlank(out.redirectUrl) ? 0 : out.redirectUrl.length()) +
                    ' matchedUserId=' +
                    resolved.matchedUserId
            );
        } catch (Exception e) {
            out.type = ROUTE_NONE;
            System.debug(
                LoggingLevel.WARN,
                LOG_PFX +
                    'discover corr=' +
                    out.correlationId +
                    ' ex=' +
                    e.getTypeName() +
                    ' msg=' +
                    summarize(e.getMessage())
            );
        }
        logRouting(out.correlationId, email, out.type, samlApi);
        return out;
    }

    @AuraEnabled(cacheable = false)
    public static LoginResult passwordLogin(String email, String password) {
        LoginResult lr = new LoginResult();
        lr.success = false;
        System.debug(
            LoggingLevel.DEBUG,
            LOG_PFX + 'passwordLogin enter id=' + LoginRouteResolver.maskIdentifier(email) + ' passwordBlank=' + String.isBlank(password)
        );
        try {
            attemptPasswordLogin(email, password, lr);
        } catch (Exception e) {
            System.debug(
                LoggingLevel.WARN,
                LOG_PFX + 'passwordLogin ex=' + e.getTypeName() + ' msg=' + summarize(e.getMessage())
            );
        }
        if (!lr.success) {
            lr.message = GENERIC_LOGIN_ERROR;
        }
        System.debug(
            LoggingLevel.INFO,
            LOG_PFX +
                'passwordLogin email=' +
                LoginRouteResolver.maskIdentifier(email) +
                ' success=' +
                lr.success +
                ' redirectLen=' +
                (lr.success && String.isNotBlank(lr.redirectUrl) ? lr.redirectUrl.length() : 0)
        );
        return lr;
    }

    private static void attemptPasswordLogin(String email, String password, LoginResult lr) {
        if (!LoginRouteResolver.isIdentifierPlausible(email) || String.isBlank(password)) {
            System.debug(
                LoggingLevel.DEBUG,
                LOG_PFX +
                    'passwordLogin abort early plausible=' +
                    LoginRouteResolver.isIdentifierPlausible(email) +
                    ' passwordBlank=' +
                    String.isBlank(password)
            );
            return;
        }
        String loginId = email.trim();
        List<User> users = LoginRouteResolver.findActiveUsersByLoginIdentifier(loginId);
        if (users.size() != 1 || String.isBlank(users[0].Username)) {
            System.debug(
                LoggingLevel.DEBUG,
                LOG_PFX + 'passwordLogin userMatchCount=' + users.size() + ' usernameBlank=' + (users.size() == 1 && String.isBlank(users[0].Username))
            );
            return;
        }
        PageReference pr = Site.login(users[0].Username, password, LoginRouteResolver.POST_LOGIN_START_URL);
        String url = (pr == null) ? null : pr.getUrl();
        System.debug(
            LoggingLevel.DEBUG,
            LOG_PFX + 'passwordLogin Site.login pageRefNull=' + (pr == null) + ' urlBlank=' + String.isBlank(url)
        );
        if (String.isBlank(url)) {
            return;
        }
        lr.success = true;
        lr.redirectUrl = url;
    }

    @TestVisible
    static String maskEmail(String email) {
        return LoginRouteResolver.maskIdentifier(email);
    }

    @TestVisible
    static Boolean isEmailPlausible(String email) {
        return LoginRouteResolver.isIdentifierPlausible(email);
    }

    private static void logRouting(String correlationId, String rawEmail, String routeType, String samlSettingApi) {
        String samlPart = String.isBlank(samlSettingApi) ? '' : (' samlSetting=' + samlSettingApi);
        System.debug(
            LoggingLevel.INFO,
            LOG_PFX +
                'corr=' +
                correlationId +
                ' email=' +
                LoginRouteResolver.maskIdentifier(rawEmail) +
                ' route=' +
                routeType +
                samlPart
        );
    }

    private static String summarize(String s) {
        if (String.isBlank(s)) {
            return '(blank)';
        }
        Integer max = 200;
        return s.length() <= max ? s : s.substring(0, max) + '…(len=' + s.length() + ')';
    }

    private static String newCorrelationId() {
        String h = EncodingUtil.convertToHex(Crypto.generateAesKey(128));
        return h.substring(0, 8) + '-' + h.substring(8, 12) + '-' + h.substring(12, 16) + '-' + h.substring(16, 20) + '-' + h.substring(20, 32);
    }
}
