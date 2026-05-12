# Feature: Email-first Experience Cloud login

### 1. Runtime Pattern

- Entry: unauthenticated visitor opens the Experience Cloud **Experience Builder** login page that hosts the **emailFirstLogin** LWC. Optional query string `startURL` / `startUrl` is read for context but **always normalized server-side to `/s/`** for post-auth landing.
- Step A — Email + Next: LWC calls **`LoginRouterService.discover(email, startUrl)`** (Guest context). Apex generates a **correlation id**, masks email in logs, trims email, rejects implausible input (returns **PASSWORD** route without revealing validity). If plausible, Apex queries **active User** by **Email** (at most one row; if zero or multiple matches, return **PASSWORD**). Loads **PermissionSetAssignment** names (non-profile sets). Queries **Client_Sso_Routing__mdt** for active **SAML** rows where `Permission_Set_Name__c` is in that set, ordered by **Priority__c** descending; takes the first row. If a row exists, resolves **`SamlSsoConfig`** by **DeveloperName** = `Saml_Setting_Api_Name__c`, then builds SSO URL via **`Auth.AuthConfiguration.getSamlSsoUrl(communityBase, '/s/', samlConfigId)`** using **`Site.getBaseUrl()`** (tests use a fixed example base). If SSO URL is blank, fall back to **PASSWORD**. Logs route type and SAML setting API name only (no full URLs, tokens, passwords). On any exception, return **PASSWORD** (no enumeration). LWC: if type **SSO** and `redirectUrl` present, **`window.location.assign(redirectUrl)`**; else advance to password step.
- Step B — Password + Sign in: LWC calls **`LoginRouterService.passwordLogin(email, password, startUrl)`**. Apex normalizes start URL to **`/s/`**, calls **`Site.login(usernameOrEmail, password, startUrl)`**. On success returns success + redirect URL string; on null or exception returns **generic** failure message (**Invalid username or password.**). LWC assigns **`window.location`** to returned URL on success.
- Invariants: no **`Site.passwordlessLogin`** with PASSWORD; no **`TwoFactorMethodsInfo`**; no client-trusted **startUrl** for redirects; **no DML** on login paths; **standard org users** who are **site members** use the same flow as partners.
- Failure handling: all client errors for password path are generic; discover never returns “user not found”; SSO build failures degrade to password step.

### 2. UI Contract

- **Layout:** White background; **compact** outer padding (no full-viewport min-height). Centered **~400px** card with light gray border, slight radius, moderate inner padding—logo and header live in Experience Builder outside this component.
- **Modes:** (1) **Email** — **Email** field only, then centered **Next** (`neutral`). (2) **Password** — **Password** field, **Back** + **Sign in** (`neutral`).
- **Footer (both steps):** Thin divider; **Forgot Your Password?** link (path: `/login` → `/ForgotPassword` swap, else `/s/ForgotPassword`).
- **Errors:** Red **form-error** text only when Apex returns a failure (`role="alert"`); no static red instructional banners.
- **Loading:** spinner inside card; buttons disabled appropriately.
- **Accessibility:** Labeled inputs; `autocomplete` on email/password.

### 3. System Components Involved

- **LoginRouterService** — Apex entrypoints for discover and password login; see [System-Components.md](System-Components.md).
- **Client_Sso_Routing__mdt** — CMDT routing table; see [System-Components.md](System-Components.md).
- **emailFirstLogin** — Experience login LWC; target **`lightningCommunity__Page`** (place on the site **Login** page in Experience Builder); see [System-Components.md](System-Components.md).
- **Login_Router_Guest** permission set — grants Apex class access to Guest; object/FLS completed in org per security review.
