@IsTest
private class CommunityLoginDiscoveryHandlerTest {
    @IsTest
    static void normalizeCommunityRootUrl_stripsLoginSuffixes() {
        System.assertEquals(
            'https://x.test',
            CommunityLoginDiscoveryHandler.normalizeCommunityRootUrl(
                new Map<String, String>{ 'CommunityUrl' => 'https://x.test/login' }
            )
        );
        System.assertEquals(
            'https://x.test',
            CommunityLoginDiscoveryHandler.normalizeCommunityRootUrl(
                new Map<String, String>{ 'CommunityUrl' => 'https://x.test/login/' }
            )
        );
        System.assertEquals(
            'https://x.test',
            CommunityLoginDiscoveryHandler.normalizeCommunityRootUrl(
                new Map<String, String>{ 'CommunityUrl' => 'https://x.test/s/login' }
            )
        );
    }

    @IsTest
    static void buildPasswordHandoff_containsPathAndEncodedEmail() {
        Map<String, String> ra = new Map<String, String>{ 'CommunityUrl' => 'https://site.example/commerce/login' };
        PageReference pr = CommunityLoginDiscoveryHandler.buildPasswordHandoffPageReference('u+c@example.org', ra);
        System.assertNotEquals(null, pr);
        String url = pr.getUrl();
        System.assert(url.contains(CommunityLoginDiscoveryHandler.PASSWORD_HANDOFF_PAGE_PATH), url);
        System.assert(url.contains(CommunityLoginDiscoveryHandler.PASSWORD_HANDOFF_EMAIL_PARAM + '='), url);
    }

    @IsTest
    static void login_passwordRoute_returnsHandoffPageReference() {
        LoginRouteResolver.TEST_ROUTING_ROWS = new List<Client_Sso_Routing__mdt>();
        String email = 'ld-handoff-' + String.valueOf(System.currentTimeMillis()) + '@routertest.invalid';
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String uniq = String.valueOf(System.currentTimeMillis());
        String alias = uniq.length() >= 8 ? uniq.substring(uniq.length() - 8) : ('ld' + uniq).substring(0, 8);
        User u = new User(
            FirstName = 'L',
            LastName = 'D',
            Email = email,
            Username = email + '.handoff',
            Alias = alias,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id,
            IsActive = true
        );
        insert u;

        Map<String, String> ra = new Map<String, String>{ 'CommunityUrl' => 'https://nz.test/login' };
        PageReference pr = new CommunityLoginDiscoveryHandler().login(email, '/s/', ra);
        System.assertNotEquals(null, pr);
        String full = pr.getUrl();
        System.assert(full.contains('finish-email-login'), full);
        System.assert(full.contains('handoffEmail='), full);
    }

    @IsTest
    static void normalizeStartUrl_alwaysReturnsCommunityHome() {
        System.assertEquals('/s/', CommunityLoginDiscoveryHandler.normalizeStartUrl('/apex/CommunitiesLanding'));
        System.assertEquals('/s/', CommunityLoginDiscoveryHandler.normalizeStartUrl(null));
    }

    @IsTest
    static void login_implausibleIdentifier_throwsLoginDiscoveryException() {
        try {
            new CommunityLoginDiscoveryHandler().login('not-an-email', '/somewhere', new Map<String, String>());
            System.assert(false, 'expected Auth.LoginDiscoveryException');
        } catch (Auth.LoginDiscoveryException e) {
            System.assertEquals('Invalid Identifier', e.getMessage());
        }
    }

    @IsTest
    static void login_unknownEmail_throwsLoginDiscoveryException() {
        try {
            new CommunityLoginDiscoveryHandler().login(
                'router-unknown-' + String.valueOf(System.currentTimeMillis()) + '@routertest.invalid',
                '/s/',
                new Map<String, String>()
            );
            System.assert(false, 'expected Auth.LoginDiscoveryException');
        } catch (Auth.LoginDiscoveryException e) {
            System.assertEquals('Invalid Identifier', e.getMessage());
        }
    }
}
