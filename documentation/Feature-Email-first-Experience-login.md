# Feature: Email-first Experience Cloud login

### 1. Runtime Pattern

**Shared routing:** **`LoginRouteResolver.resolveDiscover`** (with optional **`experienceBaseUrlOverride`**) trims input, rejects implausible identifiers (no **`User`** query), then queries **active `User`** where **Username** or **Email** equals the trimmed value (**`LIMIT 2`**). **Not exactly one** match → outcome **`NONE`**. **Exactly one** user: loads **PermissionSetAssignment** marker strings (**`PermissionSet.Name`** and **`PermissionSet.Label`** for non-profile sets), queries **`Client_Sso_Routing__mdt`** for active rows where **`Protocol__c`** is **`SAML`** and **`Permission_Set_Name__c`** is in that set (highest **`Priority__c`**). Resolves **`SamlSsoConfig`** Id from **`Saml_Sso_Config_Id__c`** or from SOQL on **`DeveloperName`**, then builds the SP-initiated URL with **`Auth.AuthConfiguration.getSamlSsoUrl(communityBase, POST_LOGIN_START_URL, samlConfigId)`**. **communityBase** comes from **`normalizeExperienceBaseUrl(experienceBaseUrlOverride)`** when the override is non-blank after normalization; otherwise **`Site.getBaseUrl()`** (trimmed). **`LoginRouterService.discover`** supplies **`window.location.origin`** from the LWC as that override. **Non-blank URL** → **`SSO`** + **`redirectUrl`**. **Blank URL** or no CMDT SAML row while markers exist → **`PASSWORD`**. **No markers** on the user → **`PASSWORD`**. **`POST_LOGIN_START_URL`** (**`/s/`**) is the relay path for **`getSamlSsoUrl`** and the post-password landing for **`Site.login`**; it is not taken from the client.

**Entry — Experience Builder Login page:** Unauthenticated visitor opens the **Login** page hosting **`emailFirstLogin`**. **Next** calls **`LoginRouterService.discover`** with the identifier and **`communityBaseUrl`**. **SSO** → full-page navigation to **`redirectUrl`**. **PASSWORD** → password step on the same LWC; **Sign in** calls **`LoginRouterService.passwordLogin`** (**`Site.login`**). **`NONE`** and unexpected errors use the generic error behavior in the UI contract. **No DML** on these paths.

**Invariants:** One active user per successful identifier resolution; **standard org users** who are **site members** follow the same routing rules.

**Failure handling (LWC):** **`discover`** maps ambiguous or failed resolution to **`NONE`** without revealing whether a user exists. **`passwordLogin`** returns a generic failure **`message`** on any unsuccessful sign-in.

### 2. UI Contract

**Login page (Experience Builder):** **`emailFirstLogin`** provides the identifier step, optional SAML redirect, and password step.

- **Layout:** White background; **compact** outer padding (no full-viewport min-height). Centered card **`max-width: 480px`**, **`width: 100%`**, light gray border, slight radius, moderate inner padding—logo and header live in Experience Builder outside this component.
- **Modes:** (1) **Email** — **Email** field only, then centered **Next** (`neutral`). (2) **Password** — read-only **Email**, **Password** field, **Back** + **Sign in** (`neutral`).
- **First-step value:** Sent to Apex as the **discover** / **passwordLogin** identifier; it may match the member’s **`User.Email`** or **`User.Username`** (must uniquely resolve one active user for routing and for password sign-in). The field label is **Email**; **`Site.login`** receives the stored **`Username`** after server-side resolution.
- **Footer (both steps):** Thin divider; **Forgot Your Password?** link (path: `/login` → `/ForgotPassword` swap, else `/s/ForgotPassword`).
- **Next (discover) result:** If **`type`** is **`SSO`** and **`redirectUrl`** is set → full-page navigation to the IdP. If **`type`** is **`PASSWORD`** → switch to password mode with no error text. Otherwise (including **`NONE`**) → stay on the first mode and set error copy to **Something went wrong. Please try again.** (same copy as Apex/transport failure on **Next**).
- **Sign in (passwordLogin) result:** On failure, show Apex **`message`** if present, else **Invalid username or password.**; on transport/exception during **Sign in**, show **Something went wrong. Please try again.**
- **Buttons:** **Next** disabled while loading or when the email value is blank after trim; **Sign in** disabled while loading or when password is blank; **Back** disabled only while loading.
- **Errors:** Red **form-error** text (`role="alert"`) for the cases above; no static red instructional banners.
- **Loading:** Spinner inside card; loading disables the primary action buttons per the rules above.
- **Accessibility:** Labeled inputs; **`autocomplete="username"`** on the first field, **`autocomplete="current-password"`** on the password field.

### 3. System Components Involved

- **LoginRouteResolver** — shared identifier → SSO/password/none resolution; see [System-Components.md](System-Components.md).
- **LoginRouterService** — **`discover`** and **`passwordLogin`** for **emailFirstLogin**; see [System-Components.md](System-Components.md).
- **Client_Sso_Routing__mdt** — CMDT routing table; see [System-Components.md](System-Components.md).
- **emailFirstLogin** — Experience login LWC; target **`lightningCommunity__Page`**; see [System-Components.md](System-Components.md).
- **Login_Router_Guest** permission set — grants Guest Apex access to **`LoginRouterService`**; see [System-Components.md](System-Components.md).
