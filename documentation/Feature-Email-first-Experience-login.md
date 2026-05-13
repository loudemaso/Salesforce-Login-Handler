# Feature: Email-first Experience Cloud login

### 1. Runtime Pattern

Unauthenticated visitor opens the **Experience Builder Login** page with **`emailFirstLogin`**. **Next** invokes **`LoginRouter.discover(identifier, communityBaseUrl)`** where **`identifier`** is the trimmed email-field value and **`communityBaseUrl`** is **`window.location.origin`**. Apex validates the identifier (non-blank, length cap, contains **`@`**, not starting or ending with **`@`**). If validation fails or no **active `User`** row matches **Username** or **Email** exactly once (**`LIMIT 2`** query), **`route`** is **`NONE`**. If exactly one user: load **non-profile** **`PermissionSetAssignment`** marker strings (**`PermissionSet.Name`** and **`PermissionSet.Label`**). If no markers, **`route`** is **`PASSWORD`**. If markers exist: select one **active** **`Client_Sso_Routing__mdt`** row whose **`Permission_Set_Name__c`** is in that marker set (**`LIMIT 1`**; no priority ordering). If no row or **`Saml_Setting_Api_Name__c`** is blank, **`route`** is **`PASSWORD`**. Otherwise resolve **`SamlSsoConfig.Id`** with **`WHERE DeveloperName = :Saml_Setting_Api_Name__c`**. If no row, **`route`** is **`PASSWORD`**. Otherwise compute community base: test seam **`TEST_COMMUNITY_BASE_URL`** when set; else **`communityBaseUrl`** trimmed with trailing slash removed when non-blank, else **`Site.getBaseUrl()`** trimmed. If base is blank, **`route`** is **`PASSWORD`**. Else call **`Auth.AuthConfiguration.getSamlSsoUrl(communityBase, '/s/', samlConfigId)`**; on blank URL or exception, **`route`** is **`PASSWORD`**; else **`route`** is **`SSO`** and **`redirectUrl`** is the initiation URL. **No DML** on **`discover`**. The LWC performs a full-page navigation to **`redirectUrl`** on **`SSO`**, advances to the password step on **`PASSWORD`**, or shows a generic error on **`NONE`**. **Sign in** calls **`LoginRouter.passwordLogin(identifier, password)`**: same user resolution rules; **`Site.login`** with server-pinned **`/s/`**; on success returns redirect URL; on any failure returns generic **`message`**. **No DML** on **`passwordLogin`**. **Observability:** this package does not emit **`System.debug`** on these paths; operators rely on product behavior and org monitoring as configured.

**Invariants:** One active user per successful routing or sign-in; post-login path **`/s/`** is fixed in Apex, not client-supplied.

**Failure handling (LWC):** **`discover`** outcomes **`NONE`** and transport errors map to the same generic first-step error copy. **`passwordLogin`** failures use Apex **`message`** or a fixed invalid-credentials string; transport errors use the same generic copy as **`discover`**.

### 2. UI Contract

**Login page (Experience Builder):** **`emailFirstLogin`** provides the identifier step, optional SAML redirect, and password step.

- **Layout:** White background; **compact** outer padding (no full-viewport min-height). Centered card **`max-width: 480px`**, **`width: 100%`**, light gray border, slight radius, moderate inner padding—logo and header live in Experience Builder outside this component.
- **Modes:** (1) **Email** — **Email** field only, then centered **Next** (`neutral`). (2) **Password** — read-only **Email**, **Password** field, **Back** + **Sign in** (`neutral`).
- **First-step value:** Sent to Apex as **`identifier`** on **`discover`** and **`passwordLogin`**; it may match the member’s **`User.Email`** or **`User.Username`** (must uniquely resolve one active user). The field label is **Email**; **`Site.login`** uses the resolved **`Username`**. **`communityBaseUrl`** is always **`window.location.origin`** on **`discover`**.
- **Footer (both steps):** Thin divider; **Forgot Your Password?** link (path: `/login` → `/ForgotPassword` swap, else `/s/ForgotPassword`).
- **Next (`discover`) result:** If **`route`** is **`SSO`** and **`redirectUrl`** is set → full-page navigation to the IdP. If **`route`** is **`PASSWORD`** → switch to password mode with no error text. Otherwise (including **`NONE`**) → stay on the first mode and set error copy to **Something went wrong. Please try again.** (same copy as transport failure on **Next**).
- **Sign in (`passwordLogin`) result:** On failure, show Apex **`message`** if present, else **Invalid username or password.**; on transport/exception during **Sign in**, show **Something went wrong. Please try again.**
- **Buttons:** **Next** disabled while loading or when the email value is blank after trim; **Sign in** disabled while loading or when password is blank; **Back** disabled only while loading.
- **Errors:** Red **form-error** text (`role="alert"`) for the cases above; no static red instructional banners.
- **Loading:** Spinner inside card; loading disables the primary action buttons per the rules above.
- **Accessibility:** Labeled inputs; **`autocomplete="username"`** on the first field, **`autocomplete="current-password"`** on the password field; read-only email on the password step uses **`read-only`** on **`lightning-input`**.

### 3. System Components Involved

- **LoginRouter** — Guest **`discover`** and **`passwordLogin`**; see [System-Components.md](System-Components.md).
- **Client_Sso_Routing__mdt** — CMDT routing table; see [System-Components.md](System-Components.md).
- **emailFirstLogin** — Experience login LWC; target **`lightningCommunity__Page`**; see [System-Components.md](System-Components.md).
- **Login_Router_Guest** permission set — grants Guest Apex access to **`LoginRouter`**; see [System-Components.md](System-Components.md).
