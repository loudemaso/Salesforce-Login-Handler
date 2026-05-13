/**
 * Platform Login Discovery handler for Experience Cloud: identifier first, then SAML via CMDT + marker sets.
 * Password routing does not use Site.passwordlessLogin(PASSWORD): that sends users to PasswordVerificationUi, which
 * loops back to /login in some Experience setups (see SSO_ExperienceCloud_EmailFirst_Login_Handoff.txt). Instead we
 * hand off to a Guest-accessible Builder page that uses LoginRouterService.passwordLogin (Site.login).
 */
global without sharing class CommunityLoginDiscoveryHandler implements Auth.LoginDiscoveryHandler {
    private static final String LOG_PFX = 'CommunityLoginDiscoveryHandler|';

    /**
     * Experience page URL path (below site base) hosting emailFirstLogin for password completion.
     * Admins must create a Builder page with this URL slug and place the LWC on it; Guest needs Login_Router_Guest.
     */
    public static final String PASSWORD_HANDOFF_PAGE_PATH = '/s/finish-email-login';
    /** Query parameter read by emailFirstLogin — keep in sync with LWC. */
    public static final String PASSWORD_HANDOFF_EMAIL_PARAM = 'handoffEmail';

    global PageReference login(String identifier, String startUrl, Map<String, String> requestAttributes) {
        logRequestContext(requestAttributes, startUrl);
        String samlCommunityBase = normalizeCommunityRootUrl(requestAttributes);
        logInfo(
            'login normalizedCommunityRoot=' +
                (String.isBlank(samlCommunityBase) ? '(blank)' : samlCommunityBase) +
                ' id=' +
                LoginRouteResolver.maskIdentifier(identifier)
        );
        LoginRouteResolver.DiscoverOutcome outcome = LoginRouteResolver.resolveDiscover(identifier, samlCommunityBase);
        if (LoginRouteResolver.ROUTE_SSO.equals(outcome.routeType) && String.isNotBlank(outcome.redirectUrl)) {
            System.debug(
                LoggingLevel.INFO,
                LOG_PFX +
                    'route=SSO id=' +
                    LoginRouteResolver.maskIdentifier(identifier) +
                    ' redirectLen=' +
                    outcome.redirectUrl.length()
            );
            return new PageReference(outcome.redirectUrl);
        }
        if (LoginRouteResolver.ROUTE_NONE.equals(outcome.routeType) || outcome.matchedUserId == null) {
            logInfo(
                'login throwing LoginDiscoveryException invalidIdentifier route=' +
                    outcome.routeType +
                    ' matchedUserId=' +
                    outcome.matchedUserId
            );
            throw new Auth.LoginDiscoveryException('Invalid Identifier');
        }

        PageReference handoff = buildPasswordHandoffPageReference(identifier, requestAttributes);
        if (handoff == null) {
            System.debug(LoggingLevel.WARN, LOG_PFX + 'passwordHandoff PageReference build failed (null)');
            throw new Auth.LoginDiscoveryException('Invalid Identifier');
        }
        String handoffUrl = handoff.getUrl();
        System.debug(
            LoggingLevel.INFO,
            LOG_PFX +
                'route=PASSWORD_HANDOFF id=' +
                LoginRouteResolver.maskIdentifier(identifier) +
                ' handoffLen=' +
                (String.isBlank(handoffUrl) ? 0 : handoffUrl.length()) +
                ' handoffSnip=' +
                snip(handoffUrl)
        );
        return handoff;
    }

    /**
     * Absolute handoff URL: community root + PASSWORD_HANDOFF_PAGE_PATH + ?handoffEmail=...
     * CommunityUrl from login discovery often ends with /login or /discover; strip those so /s/... is valid.
     */
    @TestVisible
    static PageReference buildPasswordHandoffPageReference(String identifier, Map<String, String> requestAttributes) {
        String root = normalizeCommunityRootUrl(requestAttributes);
        if (String.isBlank(root)) {
            System.debug(LoggingLevel.WARN, LOG_PFX + 'buildPasswordHandoffPageReference rootBlank=true');
            return null;
        }
        String enc = EncodingUtil.urlEncode(String.isBlank(identifier) ? '' : identifier.trim(), 'UTF-8');
        String pathAndQuery = PASSWORD_HANDOFF_PAGE_PATH + '?' + PASSWORD_HANDOFF_EMAIL_PARAM + '=' + enc;
        String full = root + pathAndQuery;
        logDbg('buildPasswordHandoffPageReference root=' + root + ' pathAndQuery=' + pathAndQuery + ' fullLen=' + full.length());
        return new PageReference(full);
    }

    @TestVisible
    static String normalizeCommunityRootUrl(Map<String, String> requestAttributes) {
        String raw = null;
        if (requestAttributes != null) {
            raw = requestAttributes.get('CommunityUrl');
        }
        if (String.isBlank(raw)) {
            raw = Site.getBaseUrl();
        }
        if (String.isBlank(raw)) {
            return null;
        }
        raw = raw.trim();
        while (raw.endsWith('/')) {
            raw = raw.substring(0, raw.length() - 1);
        }
        String lower = raw.toLowerCase();
        for (String trail : new List<String>{ '/s/login', '/login', '/discover' }) {
            if (lower.endsWith(trail)) {
                raw = raw.substring(0, raw.length() - trail.length());
                while (raw.endsWith('/')) {
                    raw = raw.substring(0, raw.length() - 1);
                }
                lower = raw.toLowerCase();
            }
        }
        return raw;
    }

    private static void logRequestContext(Map<String, String> requestAttributes, String startUrl) {
        if (requestAttributes == null || requestAttributes.isEmpty()) {
            logDbg('requestAttributes=(null or empty) startUrl=' + snip(startUrl));
            return;
        }
        List<String> keys = new List<String>(requestAttributes.keySet());
        keys.sort();
        logDbg('requestAttributeKeys=' + String.join(keys, ','));

        String communityUrl = requestAttributes.get('CommunityUrl');
        logInfo('requestAttributes.CommunityUrl raw=' + (String.isBlank(communityUrl) ? '(blank)' : communityUrl));
        logDbg(
            'requestAttributes sample Ip=' +
                requestAttributes.get('IpAddress') +
                ' Platform=' +
                requestAttributes.get('Platform') +
                ' Application=' +
                requestAttributes.get('Application')
        );
        logDbg('startUrl=' + snip(startUrl));
    }

    private static void logDbg(String msg) {
        System.debug(LoggingLevel.DEBUG, LOG_PFX + msg);
    }

    private static void logInfo(String msg) {
        System.debug(LoggingLevel.INFO, LOG_PFX + msg);
    }

    private static String snip(String s) {
        if (String.isBlank(s)) {
            return '';
        }
        Integer max = 200;
        return s.length() <= max ? s : s.substring(0, max) + '…(len=' + s.length() + ')';
    }

    /**
     * Post-auth landing is pinned to the community home prefix so callers cannot steer the session elsewhere.
     */
    @TestVisible
    static String normalizeStartUrl(String startUrl) {
        return LoginRouteResolver.POST_LOGIN_START_URL;
    }
}
