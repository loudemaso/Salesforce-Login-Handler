import { LightningElement } from 'lwc';
import discover from '@salesforce/apex/LoginRouterService.discover';
import passwordLogin from '@salesforce/apex/LoginRouterService.passwordLogin';

const STEP_EMAIL = 'email';
const STEP_PASSWORD = 'password';
const ROUTE_SSO = 'SSO';
const ROUTE_PASSWORD = 'PASSWORD';
const FALLBACK_FORGOT_PATH = '/s/ForgotPassword';
const GENERIC_CLIENT_ERROR = 'Something went wrong. Please try again.';
const GENERIC_LOGIN_ERROR = 'Invalid username or password.';

export default class EmailFirstLogin extends LightningElement {
    step = STEP_EMAIL;
    email = '';
    password = '';
    loading = false;
    errorMessage = '';

    get isEmailStep() {
        return this.step === STEP_EMAIL;
    }

    get isPasswordStep() {
        return this.step === STEP_PASSWORD;
    }

    get loadingOrEmptyEmail() {
        return this.loading || !this.email || !this.email.trim();
    }

    get loadingOrEmptyPassword() {
        return this.loading || !this.password;
    }

    // Map current `/login` URL to the standard Experience Forgot Password page; otherwise use `/s/ForgotPassword`.
    get forgotPasswordUrl() {
        try {
            const u = new URL(window.location.href);
            if (/\/login\/?$/i.test(u.pathname)) {
                u.pathname = u.pathname.replace(/\/login\/?$/i, '/ForgotPassword').replace(/\/{2,}/g, '/');
            } else {
                u.pathname = FALLBACK_FORGOT_PATH;
            }
            return u.toString();
        } catch (e) {
            return '#';
        }
    }

    handleEmailChange(event) {
        this.email = event.target.value;
        this.errorMessage = '';
    }

    handlePasswordChange(event) {
        this.password = event.target.value;
        this.errorMessage = '';
    }

    communityOrigin() {
        try {
            return window.location.origin;
        } catch (e) {
            return '';
        }
    }

    async handleNext() {
        this.errorMessage = '';
        this.loading = true;
        try {
            const result = await discover({
                email: this.email,
                communityBaseUrl: this.communityOrigin()
            });
            if (result.type === ROUTE_SSO && result.redirectUrl) {
                window.location.assign(result.redirectUrl);
                return;
            }
            if (result.type === ROUTE_PASSWORD) {
                this.step = STEP_PASSWORD;
                return;
            }
            this.errorMessage = GENERIC_CLIENT_ERROR;
        } catch (e) {
            this.errorMessage = GENERIC_CLIENT_ERROR;
        } finally {
            this.loading = false;
        }
    }

    handleBack() {
        this.errorMessage = '';
        this.password = '';
        this.step = STEP_EMAIL;
    }

    async handleSignIn() {
        this.errorMessage = '';
        this.loading = true;
        try {
            const result = await passwordLogin({
                email: this.email,
                password: this.password
            });
            if (result.success && result.redirectUrl) {
                window.location.assign(result.redirectUrl);
                return;
            }
            this.errorMessage = result.message || GENERIC_LOGIN_ERROR;
        } catch (e) {
            this.errorMessage = GENERIC_CLIENT_ERROR;
        } finally {
            this.loading = false;
        }
    }
}
