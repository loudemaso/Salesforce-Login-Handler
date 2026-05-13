@IsTest
private class LoginRouterServiceTest {
    private static Integer counter = 0;

    private static String newUniqueEmail() {
        counter++;
        return 'router-test-' + System.currentTimeMillis() + '-' + counter + '@routertest.invalid';
    }

    private static User insertTestUser(String email) {
        return insertTestUserWithCredentials(email, email + '.user');
    }

    private static User insertTestUserWithCredentials(String emailAddr, String username) {
        counter++;
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String aliasSeed = 'r' + String.valueOf(counter) + String.valueOf(System.currentTimeMillis());
        String alias = aliasSeed.length() > 8 ? aliasSeed.substring(0, 8) : aliasSeed;
        User u = new User(
            FirstName = 'Router',
            LastName = 'Test',
            Email = emailAddr,
            Username = username,
            Alias = alias,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id,
            IsActive = true
        );
        insert u;
        return u;
    }

    private static PermissionSet insertMarkerPermissionSet() {
        counter++;
        String suffix = String.valueOf(System.currentTimeMillis()) + '_' + counter;
        PermissionSet ps = new PermissionSet(
            Name = 'Login_Router_Marker_' + suffix,
            Label = 'Login Router Marker ' + suffix
        );
        insert ps;
        return ps;
    }

    private static void assignMarker(User u, PermissionSet ps) {
        insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
    }

    @IsTest
    static void maskEmail_masksLocalPart() {
        System.assertEquals('a***@example.com', LoginRouterService.maskEmail('alice@example.com'));
        System.assertEquals('***', LoginRouterService.maskEmail(null));
        System.assertEquals('***', LoginRouterService.maskEmail('not-an-email'));
    }

    @IsTest
    static void isEmailPlausible_validatesShapeAndLength() {
        System.assertEquals(false, LoginRouterService.isEmailPlausible(null));
        System.assertEquals(false, LoginRouterService.isEmailPlausible(''));
        System.assertEquals(false, LoginRouterService.isEmailPlausible('@nodomain.com'));
        System.assertEquals(false, LoginRouterService.isEmailPlausible('noat.com'));
        System.assertEquals(true, LoginRouterService.isEmailPlausible(' user@example.com '));
        String longLocal = '';
        for (Integer i = 0; i < 300; i++) {
            longLocal += 'a';
        }
        longLocal += '@x.com';
        System.assertEquals(false, LoginRouterService.isEmailPlausible(longLocal));
    }

    @IsTest
    static void discover_blankEmail_returnsNoneRoute() {
        LoginRouterService.DiscoverResult r = LoginRouterService.discover('');
        System.assertEquals('NONE', r.type);
        System.assertEquals(null, r.redirectUrl);
        System.assertNotEquals(null, r.correlationId);
    }

    @IsTest
    static void discover_unknownEmail_returnsNoneRoute() {
        LoginRouteResolver.TEST_ROUTING_ROWS = new List<Client_Sso_Routing__mdt>();
        LoginRouterService.DiscoverResult r = LoginRouterService.discover(newUniqueEmail());
        System.assertEquals('NONE', r.type);
        System.assertEquals(null, r.redirectUrl);
    }

    @IsTest
    static void discover_identifierMatchesTwoUsers_returnsNoneRoute() {
        counter++;
        String shared = 'collide-' + System.currentTimeMillis() + '-' + counter + '@routertest.invalid';
        insertTestUserWithCredentials(shared, 'collide-a-' + counter + '@routertest.invalid');
        insertTestUserWithCredentials('other-' + counter + '@routertest.invalid', shared);
        LoginRouteResolver.TEST_ROUTING_ROWS = new List<Client_Sso_Routing__mdt>();

        LoginRouterService.DiscoverResult r = LoginRouterService.discover(shared);

        System.assertEquals('NONE', r.type);
        System.assertEquals(null, r.redirectUrl);
    }

    @IsTest
    static void discover_userWithoutMarker_returnsPasswordRoute() {
        String email = newUniqueEmail();
        insertTestUser(email);
        LoginRouteResolver.TEST_ROUTING_ROWS = new List<Client_Sso_Routing__mdt>();

        LoginRouterService.DiscoverResult r = LoginRouterService.discover(email);

        System.assertEquals('PASSWORD', r.type);
        System.assertEquals(null, r.redirectUrl);
    }

    @IsTest
    static void discover_userWithMarkerButNoRoute_returnsPasswordRoute() {
        String email = newUniqueEmail();
        User u = insertTestUser(email);
        PermissionSet ps = insertMarkerPermissionSet();
        assignMarker(u, ps);
        LoginRouteResolver.TEST_ROUTING_ROWS = new List<Client_Sso_Routing__mdt>();

        LoginRouterService.DiscoverResult r = LoginRouterService.discover(email);

        System.assertEquals('PASSWORD', r.type);
        System.assertEquals(null, r.redirectUrl);
    }

    @IsTest
    static void discover_happyPath_returnsSsoRedirect() {
        String email = newUniqueEmail();
        User u = insertTestUser(email);
        PermissionSet ps = insertMarkerPermissionSet();
        assignMarker(u, ps);
        LoginRouteResolver.TEST_ROUTING_ROWS = new List<Client_Sso_Routing__mdt>{
            new Client_Sso_Routing__mdt(
                Permission_Set_Name__c = ps.Name,
                Protocol__c = 'SAML',
                Is_Active__c = true,
                Saml_Setting_Api_Name__c = 'Test_Saml_Setting'
            )
        };
        LoginRouteResolver.TEST_SSO_URL_OVERRIDE = 'https://idp.example/start';

        LoginRouterService.DiscoverResult r = LoginRouterService.discover(email);

        System.assertEquals('SSO', r.type);
        System.assertEquals('https://idp.example/start', r.redirectUrl);
    }

    @IsTest
    static void discover_happyPath_usernameIdentifier_returnsSsoRedirect() {
        String email = newUniqueEmail();
        User u = insertTestUser(email);
        PermissionSet ps = insertMarkerPermissionSet();
        assignMarker(u, ps);
        LoginRouteResolver.TEST_ROUTING_ROWS = new List<Client_Sso_Routing__mdt>{
            new Client_Sso_Routing__mdt(
                Permission_Set_Name__c = ps.Name,
                Protocol__c = 'SAML',
                Is_Active__c = true,
                Saml_Setting_Api_Name__c = 'Test_Saml_Setting'
            )
        };
        LoginRouteResolver.TEST_SSO_URL_OVERRIDE = 'https://idp.example/start';

        LoginRouterService.DiscoverResult r = LoginRouterService.discover(u.Username);

        System.assertEquals('SSO', r.type);
        System.assertEquals('https://idp.example/start', r.redirectUrl);
    }

    @IsTest
    static void discover_happyPath_samlSsoConfigIdPresentStillHonorsUrlOverride() {
        String email = newUniqueEmail();
        User u = insertTestUser(email);
        PermissionSet ps = insertMarkerPermissionSet();
        assignMarker(u, ps);
        LoginRouteResolver.TEST_ROUTING_ROWS = new List<Client_Sso_Routing__mdt>{
            new Client_Sso_Routing__mdt(
                Permission_Set_Name__c = ps.Name,
                Protocol__c = 'SAML',
                Is_Active__c = true,
                Saml_Setting_Api_Name__c = 'Test_Saml_Setting',
                Saml_Sso_Config_Id__c = '00D000000000000EAA'
            )
        };
        LoginRouteResolver.TEST_SSO_URL_OVERRIDE = 'https://idp.example/with-id-field';

        LoginRouterService.DiscoverResult r = LoginRouterService.discover(email);

        System.assertEquals('SSO', r.type);
        System.assertEquals('https://idp.example/with-id-field', r.redirectUrl);
    }

    @IsTest
    static void discover_cmdtMatchesPermissionSetLabel_returnsSsoRedirect() {
        String email = newUniqueEmail();
        User u = insertTestUser(email);
        counter++;
        PermissionSet ps = new PermissionSet(
            Name = 'Login_Router_MarkerLbl_' + String.valueOf(System.currentTimeMillis()) + '_' + counter,
            Label = 'Login Router Marker Label ' + String.valueOf(System.currentTimeMillis())
        );
        insert ps;
        assignMarker(u, ps);
        LoginRouteResolver.TEST_ROUTING_ROWS = new List<Client_Sso_Routing__mdt>{
            new Client_Sso_Routing__mdt(
                Permission_Set_Name__c = ps.Label,
                Protocol__c = 'SAML',
                Is_Active__c = true,
                Saml_Setting_Api_Name__c = 'Test_Saml_Setting'
            )
        };
        LoginRouteResolver.TEST_SSO_URL_OVERRIDE = 'https://idp.example/label-match';

        LoginRouterService.DiscoverResult r = LoginRouterService.discover(email);

        System.assertEquals('SSO', r.type);
        System.assertEquals('https://idp.example/label-match', r.redirectUrl);
    }

    @IsTest
    static void discover_routeFoundButSsoUrlMissing_returnsPasswordRoute() {
        String email = newUniqueEmail();
        User u = insertTestUser(email);
        PermissionSet ps = insertMarkerPermissionSet();
        assignMarker(u, ps);
        LoginRouteResolver.TEST_ROUTING_ROWS = new List<Client_Sso_Routing__mdt>{
            new Client_Sso_Routing__mdt(
                Permission_Set_Name__c = ps.Name,
                Protocol__c = 'SAML',
                Is_Active__c = true,
                Saml_Setting_Api_Name__c = 'Missing_Saml_Setting'
            )
        };
        // No TEST_SSO_URL_OVERRIDE: real SamlSsoConfig query returns no rows → URL is null → PASSWORD fallback.

        LoginRouterService.DiscoverResult r = LoginRouterService.discover(email);

        System.assertEquals('PASSWORD', r.type);
        System.assertEquals(null, r.redirectUrl);
    }

    @IsTest
    static void passwordLogin_blankInputs_returnsGenericError() {
        LoginRouterService.LoginResult r1 = LoginRouterService.passwordLogin('', 'pw');
        System.assertEquals(false, r1.success);
        System.assertEquals('Invalid username or password.', r1.message);

        LoginRouterService.LoginResult r2 = LoginRouterService.passwordLogin('a@b.com', '');
        System.assertEquals(false, r2.success);
        System.assertEquals('Invalid username or password.', r2.message);
    }
}
