@IsTest
private class LoginRouteResolverTest {
    @IsTest
    static void normalizeExperienceBaseUrl_nullAndBlank() {
        System.assertEquals(null, LoginRouteResolver.normalizeExperienceBaseUrl(null));
        System.assertEquals(null, LoginRouteResolver.normalizeExperienceBaseUrl(''));
        System.assertEquals(null, LoginRouteResolver.normalizeExperienceBaseUrl('   '));
    }

    @IsTest
    static void normalizeExperienceBaseUrl_trimsTrailingSlashAndLoginPaths() {
        System.assertEquals(
            'https://org--sb.my.site.com',
            LoginRouteResolver.normalizeExperienceBaseUrl('https://org--sb.my.site.com/')
        );
        System.assertEquals(
            'https://org--sb.my.site.com',
            LoginRouteResolver.normalizeExperienceBaseUrl('https://org--sb.my.site.com/login')
        );
        System.assertEquals(
            'https://org--sb.my.site.com',
            LoginRouteResolver.normalizeExperienceBaseUrl('https://org--sb.my.site.com/s/login')
        );
    }
}
