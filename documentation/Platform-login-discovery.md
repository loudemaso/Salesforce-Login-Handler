# Platform login discovery

Experience Cloud **login discovery** is the primary entry: Salesforce shows the hosted identifier step, then calls **`CommunityLoginDiscoveryHandler`**, which implements **`Auth.LoginDiscoveryHandler`**. See the [LoginDiscoveryHandler](https://developer.salesforce.com/docs/atlas.en-us.apexref.meta/apexref/apex_interface_Auth_LoginDiscoveryHandler.htm) interface and Salesforce Help on [passwordless login in Apex](https://help.salesforce.com/s/articleView?id=experience.external_identity_passwordless_login_in_apex.htm&type=5) where relevant to the platform contract.

## Runtime contract

- **`login(identifier, startUrl, requestAttributes)`** calls **`LoginRouteResolver.resolveDiscover(identifier, communityRoot)`**. **`communityRoot`** comes from **`CommunityUrl`** in **`requestAttributes`** (trailing **`/login`**, **`/s/login`**, or **`/discover`** removed), falling back to **`Site.getBaseUrl()`** when **`CommunityUrl`** is blank. That root is the first argument to **`Auth.AuthConfiguration.getSamlSsoUrl`** so SP-initiated SAML uses the Experience **`my.site.com`** host.
- **SSO:** returns **`new PageReference(redirectUrl)`** when resolution is **`SSO`** with a non-blank SAML initiation URL.
- **Password:** returns a **`PageReference`** to the Guest-accessible Builder **handoff** page (**`/s/finish-email-login`** by default, query **`handoffEmail=`** + identifier). **`emailFirstLogin`** on that page calls **`LoginRouterService.passwordLogin`**, which uses **`Site.login`**. The handler does **not** use **`Site.passwordlessLogin(..., PASSWORD)`** for this path, because that API can send the browser through **`PasswordVerificationUi`** and back to **`/login`** in some Experience setups (see [`SSO_ExperienceCloud_EmailFirst_Login_Handoff.txt`](../SSO_ExperienceCloud_EmailFirst_Login_Handoff.txt)).
- **Invalid / unknown / ambiguous identifier:** throws **`Auth.LoginDiscoveryException('Invalid Identifier')`**.

## Setup

Assign **`CommunityLoginDiscoveryHandler`** in **Login & Registration**, publish the **handoff** page and Guest access per [README.md](../README.md), and configure **CMDT**, **SAML**, and **User** / **PermissionSetAssignment** visibility as described there.

## Custom Builder login (no discovery)

To use **emailFirstLogin** on the main **Login** page without login discovery, follow the README section for **Login Page Type = Experience Builder Page** and the same Guest and CMDT steps.
