@IsTest
private class LoginRouterTest {
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
        String aliasSeed = 'r' + counter + System.currentTimeMillis();
        User u = new User(
            FirstName = 'Router',
            LastName = 'Test',
            Email = emailAddr,
            Username = username,
            Alias = aliasSeed.length() > 8 ? aliasSeed.substring(0, 8) : aliasSeed,
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
    static void discover_blankIdentifier_returnsNone() {
        LoginRouter.DiscoverResponse r = LoginRouter.discover('', null);
        System.assertEquals('NONE', r.route);
        System.assertEquals(null, r.redirectUrl);
    }

    @IsTest
    static void discover_implausibleIdentifiers_returnNone() {
        System.assertEquals('NONE', LoginRouter.discover('@nodomain.com', null).route);
        System.assertEquals('NONE', LoginRouter.discover('noat.com', null).route);
        System.assertEquals('NONE', LoginRouter.discover('user@', null).route);

        String longLocal = '';
        for (Integer i = 0; i < 300; i++) {
            longLocal += 'a';
        }
        System.assertEquals('NONE', LoginRouter.discover(longLocal + '@x.com', null).route);
    }

    @IsTest
    static void discover_unknownIdentifier_returnsNone() {
        LoginRouter.TEST_ROUTING_ROWS = new List<Client_Sso_Routing__mdt>();
        LoginRouter.DiscoverResponse r = LoginRouter.discover(newUniqueEmail(), null);
        System.assertEquals('NONE', r.route);
        System.assertEquals(null, r.redirectUrl);
    }

    @IsTest
    static void discover_identifierMatchesTwoUsers_returnsNone() {
        counter++;
        String shared = 'collide-' + System.currentTimeMillis() + '-' + counter + '@routertest.invalid';
        insertTestUserWithCredentials(shared, 'collide-a-' + counter + '@routertest.invalid');
        insertTestUserWithCredentials('other-' + counter + '@routertest.invalid', shared);
        LoginRouter.TEST_ROUTING_ROWS = new List<Client_Sso_Routing__mdt>();

        LoginRouter.DiscoverResponse r = LoginRouter.discover(shared, null);
        System.assertEquals('NONE', r.route);
        System.assertEquals(null, r.redirectUrl);
    }

    @IsTest
    static void discover_userWithoutMarker_returnsPassword() {
        String email = newUniqueEmail();
        insertTestUser(email);
        LoginRouter.TEST_ROUTING_ROWS = new List<Client_Sso_Routing__mdt>();

        LoginRouter.DiscoverResponse r = LoginRouter.discover(email, null);
        System.assertEquals('PASSWORD', r.route);
        System.assertEquals(null, r.redirectUrl);
    }

    @IsTest
    static void discover_userWithMarkerButNoRoutingRow_returnsPassword() {
        String email = newUniqueEmail();
        User u = insertTestUser(email);
        PermissionSet ps = insertMarkerPermissionSet();
        assignMarker(u, ps);
        LoginRouter.TEST_ROUTING_ROWS = new List<Client_Sso_Routing__mdt>();

        LoginRouter.DiscoverResponse r = LoginRouter.discover(email, null);
        System.assertEquals('PASSWORD', r.route);
        System.assertEquals(null, r.redirectUrl);
    }

    @IsTest
    static void discover_happyPath_returnsSsoRedirect() {
        String email = newUniqueEmail();
        User u = insertTestUser(email);
        PermissionSet ps = insertMarkerPermissionSet();
        assignMarker(u, ps);
        LoginRouter.TEST_ROUTING_ROWS = new List<Client_Sso_Routing__mdt>{
            new Client_Sso_Routing__mdt(
                Permission_Set_Name__c = ps.Name,
                Is_Active__c = true,
                Saml_Setting_Api_Name__c = 'Test_Saml_Setting'
            )
        };
        LoginRouter.TEST_SSO_URL_OVERRIDE = 'https://idp.example/start';

        LoginRouter.DiscoverResponse r = LoginRouter.discover(email, null);
        System.assertEquals('SSO', r.route);
        System.assertEquals('https://idp.example/start', r.redirectUrl);
    }

    @IsTest
    static void discover_happyPath_usernameIdentifier_returnsSsoRedirect() {
        String email = newUniqueEmail();
        User u = insertTestUser(email);
        PermissionSet ps = insertMarkerPermissionSet();
        assignMarker(u, ps);
        LoginRouter.TEST_ROUTING_ROWS = new List<Client_Sso_Routing__mdt>{
            new Client_Sso_Routing__mdt(
                Permission_Set_Name__c = ps.Name,
                Is_Active__c = true,
                Saml_Setting_Api_Name__c = 'Test_Saml_Setting'
            )
        };
        LoginRouter.TEST_SSO_URL_OVERRIDE = 'https://idp.example/start';

        LoginRouter.DiscoverResponse r = LoginRouter.discover(u.Username, null);
        System.assertEquals('SSO', r.route);
        System.assertEquals('https://idp.example/start', r.redirectUrl);
    }

    @IsTest
    static void discover_cmdtMatchesPermissionSetLabel_returnsSsoRedirect() {
        String email = newUniqueEmail();
        User u = insertTestUser(email);
        counter++;
        PermissionSet ps = new PermissionSet(
            Name = 'Login_Router_MarkerLbl_' + System.currentTimeMillis() + '_' + counter,
            Label = 'Login Router Marker Label ' + System.currentTimeMillis()
        );
        insert ps;
        assignMarker(u, ps);
        LoginRouter.TEST_ROUTING_ROWS = new List<Client_Sso_Routing__mdt>{
            new Client_Sso_Routing__mdt(
                Permission_Set_Name__c = ps.Label,
                Is_Active__c = true,
                Saml_Setting_Api_Name__c = 'Test_Saml_Setting'
            )
        };
        LoginRouter.TEST_SSO_URL_OVERRIDE = 'https://idp.example/label-match';

        LoginRouter.DiscoverResponse r = LoginRouter.discover(email, null);
        System.assertEquals('SSO', r.route);
        System.assertEquals('https://idp.example/label-match', r.redirectUrl);
    }

    @IsTest
    static void discover_routingRowFoundButSamlSettingMissing_returnsPassword() {
        String email = newUniqueEmail();
        User u = insertTestUser(email);
        PermissionSet ps = insertMarkerPermissionSet();
        assignMarker(u, ps);
        LoginRouter.TEST_ROUTING_ROWS = new List<Client_Sso_Routing__mdt>{
            new Client_Sso_Routing__mdt(
                Permission_Set_Name__c = ps.Name,
                Is_Active__c = true,
                Saml_Setting_Api_Name__c = 'Missing_Saml_Setting'
            )
        };
        // No TEST_SSO_URL_OVERRIDE: real SamlSsoConfig query returns no rows → URL is null → PASSWORD fallback.

        LoginRouter.DiscoverResponse r = LoginRouter.discover(email, null);
        System.assertEquals('PASSWORD', r.route);
        System.assertEquals(null, r.redirectUrl);
    }

    @IsTest
    static void passwordLogin_blankInputs_returnGenericError() {
        LoginRouter.LoginResult r1 = LoginRouter.passwordLogin('', 'pw');
        System.assertEquals(false, r1.success);
        System.assertEquals('Invalid username or password.', r1.message);

        LoginRouter.LoginResult r2 = LoginRouter.passwordLogin('a@b.com', '');
        System.assertEquals(false, r2.success);
        System.assertEquals('Invalid username or password.', r2.message);
    }
}
