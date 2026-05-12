@IsTest
private class LoginRouterServiceTest {
    @IsTest
    static void normalizeStartUrl_alwaysReturnsCommunityHome() {
        System.assertEquals('/s/', LoginRouterService.normalizeStartUrl(null));
        System.assertEquals('/s/', LoginRouterService.normalizeStartUrl(''));
        System.assertEquals('/s/', LoginRouterService.normalizeStartUrl('/apex/CommunitiesLanding'));
        System.assertEquals('/s/', LoginRouterService.normalizeStartUrl('https://evil.example/phish'));
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
    static void discover_blankEmail_returnsPasswordRoute() {
        LoginRouterService.DiscoverResult r = LoginRouterService.discover('', '/apex/x');
        System.assertEquals('PASSWORD', r.type);
        System.assertEquals(null, r.redirectUrl);
        System.assertEquals('/s/', r.normalizedStartUrl);
        System.assertNotEquals(null, r.correlationId);
    }

    @IsTest
    static void passwordLogin_blankInputs_returnsGenericError() {
        LoginRouterService.LoginResult r1 = LoginRouterService.passwordLogin('', 'pw', '/x');
        System.assertEquals(false, r1.success);
        System.assertEquals('Invalid username or password.', r1.message);

        LoginRouterService.LoginResult r2 = LoginRouterService.passwordLogin('a@b.com', '', '/x');
        System.assertEquals(false, r2.success);
        System.assertEquals('Invalid username or password.', r2.message);
    }
}
