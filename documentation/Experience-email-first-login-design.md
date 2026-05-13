# Experience Cloud email-first login (design)

## Runtime

- **Login** uses **Experience Builder** with the **`emailFirstLogin`** LWC on the site **Login** page (**Login Page Type** = **Experience Builder Page**).
- **Guest** calls **`LoginRouterService.discover`** with the identifier and **`window.location.origin`** so **`Auth.AuthConfiguration.getSamlSsoUrl`** receives the correct Experience host when **`Site.getBaseUrl()`** in the Guest transaction is not the community root.
- **SSO:** navigate to the SAML initiation URL returned by Apex.
- **Password:** same LWC collects the password; **`LoginRouterService.passwordLogin`** uses **`Site.login`** with a server-pinned post-login path (**`/s/`**).

## Metadata

- **Marker permission sets** (no privileges required) identify which SSO client a user belongs to.
- **`Client_Sso_Routing__mdt`** maps marker set name or label to a **SAML Single Sign-On Setting** (`DeveloperName` and optional **`SamlSsoConfig` Id**). New clients add metadata and assignments only; no Apex edits.

## Org prerequisites

- **SAML** enabled under **Setup → Single Sign-On Settings**.
- **Guest** can read **`User`** (and **`PermissionSetAssignment`** when needed) per your security model; **`Login_Router_Guest`** grants Apex access to **`LoginRouterService`**.

For full setup and component contracts, see [README.md](../README.md) and [System-Components.md](System-Components.md).
