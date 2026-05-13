# Alternative runtime: `Auth.LoginDiscoveryHandler` (platform login discovery)

This note ties Salesforce’s documented **login discovery** APIs to why this repository uses a **custom LWC + Guest `discover`** path today, and when migrating to a handler is worth revisiting—especially if you want to avoid storing a **`SamlSsoConfig` Id** in CMDT.

## What Salesforce documents

### `Auth.LoginDiscoveryHandler`

The Apex interface is described in the [LoginDiscoveryHandler Interface](https://developer.salesforce.com/docs/atlas.en-us.apexref.meta/apexref/apex_interface_Auth_LoginDiscoveryHandler.htm) (Apex Reference). Summary:

- You implement **`login(identifier, startUrl, requestAttributes)`** as the server entry for **identifier-first** login (email, phone, etc.).
- The sample flow resolves a unique user, then uses a helper (e.g. **`discoveryResult`**) that:
  - First tries **`getSsoRedirect(user, startUrl, requestAttributes)`** — “look up whether the user should log in with **SAML** or an **Auth Provider** and return the URL to initialize SSO.”
  - If that returns null, it falls back to **`Site.passwordlessLogin(user.Id, methods, startUrl)`** with **`Auth.VerificationMethod`** values such as **EMAIL**, **SMS**, or **PASSWORD**.

That pattern runs in Salesforce’s **login discovery** flow (configured for the org / Experience identity experience), **not** as an `@AuraEnabled` call from the Experience **Guest** user on a Builder login page. In practice, that difference matters: **Guest** users often **cannot** read **`SamlSsoConfig`** by `DeveloperName`, which is why the LWC path in this repo may need **`Saml_Sso_Config_Id__c`** or another workaround.

### Passwordless login in Apex (Experience / identity)

Salesforce Help covers using Apex-driven flows with **`Site.passwordlessLogin`** in the context of external identity / Experience login (see [External identity: passwordless login in Apex](https://help.salesforce.com/s/articleView?id=experience.external_identity_passwordless_login_in_apex.htm&type=5)). That aligns with the **`LoginDiscoveryHandler`** examples that branch on verified email/SMS and then call **`Site.passwordlessLogin`**.

## How this relates to **this** repository

The project handoff ([`SSO_ExperienceCloud_EmailFirst_Login_Handoff.txt`](../SSO_ExperienceCloud_EmailFirst_Login_Handoff.txt)) already evaluated **Experience “Login Discovery” + `Auth.LoginDiscoveryHandler`** (option A) and **`Site.passwordlessLogin(..., PASSWORD, ...)`** (option B). In that environment:

- **`TwoFactorMethodsInfo`** was not queryable as expected.
- **`Site.passwordlessLogin` with `VerificationMethod.PASSWORD`** led to **`PasswordVerificationUi`** / **`/_ui/identity/verification/...`** loops and unreliable password entry.

That is why the **durable** approach in this repo is **custom Builder login + `Site.login`** for the password path, and **`LoginRouterService.discover`** for email/username → SSO vs password—documented in [Feature-Email-first-Experience-login.md](Feature-Email-first-Experience-login.md).

## If you want to avoid **`Saml_Sso_Config_Id__c`**

| Approach | Pros | Cons |
| --- | --- | --- |
| **Stay on LWC + Guest `discover`** | Matches current handoff; **`Site.login`** password path; full control of UX. | Guest usually **cannot** SOQL **`SamlSsoConfig`** by name → need **Id in CMDT** (or similar) unless Salesforce grants Guest read (atypical). |
| **Move SSO resolution to `Auth.LoginDiscoveryHandler`** | Same platform pattern as the Apex doc: implement **`getSsoRedirect`** and return the SAML initiation **`PageReference`**; SOQL on **`SamlSsoConfig`** may succeed in the **handler** context without stuffing Ids into CMDT. | Reintroduces **login discovery** product surface; password path likely uses **`Site.passwordlessLogin`** (see doc above)—**re-validate** in your org that you do not hit the **`PasswordVerificationUi`** issues the handoff called out. May change **Login Page Type** / identity configuration vs Builder-only login. |
| **Hybrid** (e.g. discovery for SSO only, custom page for password) | Theoretical; non-trivial to keep one coherent UX. | High design and test cost. |

## Practical recommendation

1. **Short term (this repo’s architecture):** Treat **`Saml_Sso_Config_Id__c`** as an optional, Guest-safe bridge for **`getSamlSsoUrl`** when name-based **`SamlSsoConfig`** lookup is not available to Guest.
2. **Long term (if you dislike Id in metadata):** Prototype **`Auth.LoginDiscoveryHandler`** again with a **minimal** implementation: resolve user → **`getSsoRedirect`** using **only** `DeveloperName` (no Id field), then explicitly test **password** and **SAML** in the same org where you previously saw **`PasswordVerificationUi`** loops. If password remains solid, you can consider retiring the custom LWC path for that site.
