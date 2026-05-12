import { LightningElement, track } from 'lwc';
import discover from '@salesforce/apex/LoginRouterService.discover';
import passwordLogin from '@salesforce/apex/LoginRouterService.passwordLogin';

const STEP_EMAIL = 'email';
const STEP_PASSWORD = 'password';

export default class EmailFirstLogin extends LightningElement {
    @track step = STEP_EMAIL;
    @track email = '';
    @track password = '';
    @track loading = false;
    @track errorMessage = '';

    connectedCallback() {
        this.readStartUrlFromLocation();
    }

    readStartUrlFromLocation() {
        try {
            const params = new URLSearchParams(window.location.search);
            const raw = params.get('startURL') || params.get('startUrl') || '';
            this._startUrl = raw || '/s/';
        } catch (e) {
            this._startUrl = '/s/';
        }
    }

    _startUrl = '/s/';

    get isEmailStep() {
        return this.step === STEP_EMAIL;
    }

    get isPasswordStep() {
        return this.step === STEP_PASSWORD;
    }

    /** Map current .../login URL to standard Experience Forgot Password page */
    get forgotPasswordUrl() {
        try {
            const u = new URL(window.location.href);
            const path = u.pathname || '';
            if (/\/login\/?$/i.test(path)) {
                u.pathname = path.replace(/\/login\/?$/i, '/ForgotPassword').replace(/\/{2,}/g, '/');
            } else {
                u.pathname = '/s/ForgotPassword';
            }
            return u.toString();
        } catch (e) {
            return '#';
        }
    }

    get loadingOrEmptyEmail() {
        return this.loading || !this.email || !this.email.trim();
    }

    get loadingOrEmptyPassword() {
        return this.loading || !this.password;
    }

    handleEmailChange(event) {
        this.email = event.target.value;
        this.errorMessage = '';
    }

    handlePasswordChange(event) {
        this.password = event.target.value;
        this.errorMessage = '';
    }

    async handleNext() {
        this.errorMessage = '';
        this.loading = true;
        try {
            const result = await discover({
                email: this.email,
                startUrl: this._startUrl
            });
            if (result.type === 'SSO' && result.redirectUrl) {
                window.location.assign(result.redirectUrl);
                return;
            }
            this.step = STEP_PASSWORD;
        } catch (e) {
            this.errorMessage = 'Something went wrong. Please try again.';
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
                password: this.password,
                startUrl: this._startUrl
            });
            if (result.success && result.redirectUrl) {
                window.location.assign(result.redirectUrl);
                return;
            }
            this.errorMessage = result.message || 'Invalid username or password.';
        } catch (e) {
            this.errorMessage = 'Something went wrong. Please try again.';
        } finally {
            this.loading = false;
        }
    }
}
