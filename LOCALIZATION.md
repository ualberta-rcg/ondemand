# Open OnDemand Internationalization & Localization Guide

This guide documents Open OnDemand's end-to-end internationalization (`i18n`) and localization (`l10n`) architecture, site configuration, multi-language interactive application development, MOTD localization, and automated catalog synchronization tools.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
   - [Locale Resolution Contract](#locale-resolution-contract)
   - [Cross-App Transport (`ood_locale` Cookie)](#cross-app-transport-ood_locale-cookie)
   - [BCP 47 Normalization & Fallback Chains](#bcp-47-normalization--fallback-chains)
   - [Locale-Isolated Caches](#locale-isolated-caches)
   - [Client-Side JavaScript, DataTables & Uppy Localization](#client-side-javascript-datatables--uppy-localization)
   - [Shipped Regional & Themed Locales](#shipped-regional--themed-locales)
2. [Site Administrator Guide](#2-site-administrator-guide)
   - [Configuring Default & Supported Locales](#configuring-default--supported-locales)
   - [Localizing `ondemand.d` Branding, Menus & Support Tickets](#localizing-ondemandd-branding-menus--support-tickets)
   - [Configuring Multi-Language MOTDs](#configuring-multi-language-motds)
   - [Site-Specific Locale Overrides (`/etc/ood/config/locales`)](#site-specific-locale-overrides-etcoodconfiglocales)
   - [Auto-Generating & Synchronizing Missing Locale Files](#auto-generating--synchronizing-missing-locale-files)
   - [Multi-Login-Node Load-Balanced Deployments](#multi-login-node-load-balanced-deployments)
3. [Multi-Language App Developer Guide](#3-multi-language-app-developer-guide)
   - [Application Directory Layout](#application-directory-layout)
   - [Localizing `manifest.yml` & `form.yml` Attributes](#localizing-manifestyml--formyml-attributes)
   - [Localizing `view.html.erb` Connect Buttons & Session Instructions](#localizing-viewhtmlerb-connect-buttons--session-instructions)
   - [Localizing App Categories & Subcategories](#localizing-app-categories--subcategories)
   - [Generating App Locale Files Automatically](#generating-app-locale-files-automatically)
4. [Contributor & Testing Guide](#4-contributor--testing-guide)
   - [Adding or Updating UI Strings](#adding-or-updating-ui-strings)
   - [Adding a New Regional or Custom/Themed Locale](#adding-a-new-regional-or-customthemed-locale)
   - [Running the Localization Test & CI Suite](#running-the-localization-test--ci-suite)

---

## 1. Architecture Overview

### Locale Resolution Contract

Every Open OnDemand web surface resolves the active user locale in the same deterministic precedence order (`OodLocale.resolve`):

1. **Per-user persisted setting** (`~/.config/ondemand/settings.yml` key `locale`, written when a user selects a language in the navbar dropdown).
2. **Cross-app `ood_locale` cookie** (`path: /`, `SameSite=Lax`, `Secure` over HTTPS).
3. **Browser `Accept-Language` header** (RFC 9110 quality-weighted negotiation against `supported_locales`).
4. **Site default `locale`** configured in `/etc/ood/config/ondemand.d/*.yml` (recommended: `"en-CA"`).
5. **Built-in fallback** (`:en`).

When a site configures regional locales only (for example `en-CA` and `en-GB` without standalone `en`), legacy bare tags such as `locale: "en"` in an existing user's `settings.yml` or cookie automatically resolve to the first matching regional variant in `supported_locales` (e.g., `en-CA`).

### Cross-App Transport (`ood_locale` Cookie)

Open OnDemand comprises multiple independent Passenger and Node.js applications under `/pun/sys/*`:

- **Dashboard (`apps/dashboard`)**: Rails application that renders the top navbar `#locale-switcher` dropdown (styled in uppercase `XX-YY` tags), persists user selection to `~/.config/ondemand/settings.yml` via `POST /settings`, and emits the `ood_locale` cookie.
- **Job Composer (`apps/myjobs`)**: Separate Rails application with its own `OodLocale` module and `config/locales/<locale>.yml` catalogs; reads `settings.yml` and `ood_locale` so switching languages in the Dashboard immediately localizes Job Composer.
- **Web Shell (`apps/shell`)**: Express/Node.js terminal app (`utils/i18n.js` + `locales/<locale>.json`); resolves `settings.yml` -> `ood_locale` -> `Accept-Language` -> `OOD_LOCALE` without requiring external npm dependencies.
- **noVNC Client (`apps/dashboard/public/noVNC-1.3.0/app/localization.js`)**: Browser VNC viewer that prioritizes the `ood_locale` cookie over `navigator.languages`, preventing secondary browser languages from overriding the user's selected Open OnDemand language and supporting sibling regional fallbacks (e.g., `pt-PT` -> `pt_BR`).

### BCP 47 Normalization & Fallback Chains

- Ruby `I18n` historically accepts underscore tags (such as `ja_JP`), whereas HTML `lang="..."`, HTTP cookies, and JavaScript `Intl.NumberFormat` / `Intl.DateTimeFormat` / `Intl.PluralRules` strictly require hyphenated **BCP 47** tags (`ja-JP`, `en-CA`, `fr-CA`). Calling `Intl` APIs with `ja_JP` raises `RangeError: Incorrect locale information provided`.
- `OodLocale.canonical_bcp47(tag)` normalizes any tag (`ja_jp`, `ja_JP`, `en-ca`) into canonical BCP 47 (`ja-JP`, `en-CA`) for `<html lang="...">`, `ood_locale`, `settings.yml`, and inline JSON payloads while mapping cleanly back to the underlying `I18n.available_locales` symbol.
- `config/initializers/locales.rb` configures `I18n::Backend::Fallbacks` so every regional variant falls back through its primary language (when available) to `:en` (`config/locales/en.yml`, retained internally as the base fallback dictionary even when standalone `EN` is excluded from the UI dropdown).

### Locale-Isolated Caches

Multi-language rendering inside long-lived Per-User NGINX (PUN) Passenger processes requires every cached object that embeds translated titles, descriptions, or form labels to include `I18n.locale` in its cache key:

- `BatchConnect::App.from_token` caches under `batch_connect_app/#{I18n.locale}/#{token}`.
- `OodApp` memoizes `manifest`, `category`, and `subcategory` per `I18n.locale`.
- `BatchConnect::Session#app` and `BatchConnect::Session#display_title` re-evaluate per `I18n.locale` so active session cards update dynamically when switching languages.

### Client-Side JavaScript, DataTables & Uppy Localization

- **Server-Rendered JS Catalog (`#ood_i18n`)**: `ApplicationHelper#dashboard_js_translations` deep-merges `dashboard.js` across `I18n.fallbacks[I18n.locale]` (preventing partial locale hashes from masking English subkeys) and emits `<script id="ood_i18n" type="application/json">`.
- **`app/javascript/i18n.js`**: Provides `oodLocale()`, `t(key, vars)` (with `%{var}` interpolation and `Intl.PluralRules` pluralization), `formatNumber()`, `formatDateTime()`, and `dataTablesLanguage()` across all Stimulus controllers and legacy jQuery modules.
- **Offline DataTables 2.x Language Packs (`app/javascript/datatables_i18n.js`)**: Bundles offline DataTables translations for all 31 regional locales so air-gapped HPC clusters never make external CDN requests.
- **Uppy File Uploader**: `ApplicationHelper#uppy_locale_json` injects localized `dashboard.uppy.strings` directly into `#ood_config[data-uppy-locale]`.

### Shipped Regional & Themed Locales

Open OnDemand ships **100% key-parity catalogs** across **31 regional `xx-YY` locales** in `apps/dashboard`, `apps/myjobs`, `apps/shell`, and all 9 built-in applications (`activejobs`, `bc_desktop`, `file-editor`, `files`, `module-browser`, `myjobs`, `projects`, `shell`, `system-status`):

| Group | Locale Tags (`XX-YY` in Switcher) |
| --- | --- |
| **Default & English / French Variants** | `en-CA` (*default*), `en-GB`, `fr-CA`, `fr-FR` |
| **22 Additional Official EU Languages** | `bg-BG`, `cs-CZ`, `da-DK`, `de-DE`, `el-GR`, `es-ES`, `et-EE`, `fi-FI`, `ga-IE`, `hr-HR`, `hu-HU`, `it-IT`, `lt-LT`, `lv-LV`, `mt-MT`, `nl-NL`, `pl-PL`, `pt-PT`, `ro-RO`, `sk-SK`, `sl-SI`, `sv-SE` |
| **Asia & Middle East** | `ja-JP` (`ja_JP.yml` in Dashboard), `zh-CN` (Simplified Chinese), `fa-IR` (Persian, RTL) |
| **Fun / Themed English Dialects** | `en-HG` (*Hitchhiker's Guide — Don't Panic*), `en-CP` (*Cyberpunk — Netrunner*) |

---

## 2. Site Administrator Guide

### Configuring Default & Supported Locales

Create `/etc/ood/config/ondemand.d/localization.yml` to set the site default (`en-CA`) and choose which locales appear in the `#locale-switcher` navbar dropdown.

To enable **all 31 regional `xx-YY` locales** (excluding standalone `en`) with `en-CA` first:

```yaml
# /etc/ood/config/ondemand.d/localization.yml
locale: "en-CA"
supported_locales: "regional"
```

Or specify an explicit ordered list of regional tags:

```yaml
# /etc/ood/config/ondemand.d/localization.yml
locale: "en-CA"
supported_locales:
  - "en-CA"
  - "en-GB"
  - "fr-CA"
  - "fr-FR"
  - "de-DE"
  - "es-ES"
  - "ja-JP"
  - "zh-CN"
  - "fa-IR"
  - "en-HG"
  - "en-CP"
```

Environment variable equivalents (`OOD_LOCALE="en-CA"` and `OOD_SUPPORTED_LOCALES="en-CA,en-GB,fr-CA,..."` or `OOD_SUPPORTED_LOCALES="regional"`) are also honored by Dashboard, Job Composer, and Shell.

### Localizing `ondemand.d` Branding, Menus & Support Tickets

Configuration properties resolved through `LocalizedValue.resolve` accept either a plain string (backward-compatible) or a per-locale YAML map with automatic primary-language and `:en` fallback:

```yaml
# /etc/ood/config/ondemand.d/branding.yml
dashboard_title:
  en-CA: "Research Computing Portal"
  en-GB: "Research Computing Portal"
  fr-CA: "Portail de calcul informatique de pointe"
  de-DE: "Portal für wissenschaftliches Rechnen"
  en-HG: "Heart of Gold Improbability Portal"
  en-CP: "Night City Mainframe Subnet"

help_menu:
  - group:
      en-CA: "Documentation & Training"
      fr-CA: "Documentation et formation"
      de-DE: "Dokumentation & Schulung"
  - title:
      en-CA: "Getting Started Guide"
      fr-CA: "Guide de démarrage"
      de-DE: "Erste Schritte"
    icon: "fas://rocket"
    url: "https://docs.example.edu/getting-started"

support_ticket:
  description:
    en-CA: |
      Submit a support request to the Research Computing team. Include job IDs and steps to reproduce.
    fr-CA: |
      Soumettez une demande de soutien à l'équipe de calcul. Indiquez les identifiants de tâches et les étapes pour reproduire le problème.
```

The same locale-map structure works in `nav_bar`, `interactive_apps_menu`, `help_bar`, and `custom_pages` titles/groups.

### Configuring Multi-Language MOTDs

`MotdFile` automatically discovers localized Message of the Day files adjacent to `MOTD_PATH` before falling back to the base `MOTD_PATH` file.

1. Configure `MOTD_PATH` and `MOTD_FORMAT` (for example in `/etc/ood/config/apps/dashboard/env`):
   ```bash
   MOTD_PATH="/etc/ood/config/ondemand.d/motd"
   MOTD_FORMAT="markdown"
   ```
   Supported `MOTD_FORMAT` values: `markdown`, `text`, `osc`, `markdown_erb`, `text_erb`, and `rss`.

2. Place localized sibling files next to `MOTD_PATH` using canonical BCP 47 (`<path>.<locale>`) or primary language (`<path>.<lang>`):
   ```text
   /etc/ood/config/ondemand.d/motd          # Default (e.g., en-CA)
   /etc/ood/config/ondemand.d/motd.fr-CA    # Canadian French
   /etc/ood/config/ondemand.d/motd.fr       # Generic French fallback (fr-FR, etc.)
   /etc/ood/config/ondemand.d/motd.de-DE    # German
   /etc/ood/config/ondemand.d/motd.ja-JP    # Japanese
   /etc/ood/config/ondemand.d/motd.en-HG    # Hitchhiker's Guide dialect
   /etc/ood/config/ondemand.d/motd.en-CP    # Cyberpunk dialect
   ```
   If `MOTD_PATH` has an extension (such as `/etc/motd.md`), both `/etc/motd.md.fr-CA` and `/etc/motd.fr-CA.md` are recognized automatically.

### Site-Specific Locale Overrides (`/etc/ood/config/locales`)

Dashboard loads all `*.yml` files in `/etc/ood/config/locales/` (`Configuration.locales_root`) **after** the built-in `apps/dashboard/config/locales/*.yml` catalogs.

- **Best Practice**: Put site-specific keys for custom widgets/partials under a dedicated top-level namespace (e.g., `site:` or your cluster name) rather than copying the entire `en-CA.yml` file into `/etc/ood/config/locales/`. Copying a full upstream file freezes those keys across future Open OnDemand upgrades.
- Example `/etc/ood/config/locales/fr-CA.yml` (note that for Japanese in Dashboard, use `ja_JP` as the root key in `ja_JP.yml` to match Dashboard's `I18n.locale` symbol):
  ```yaml
  ---
  fr-CA:
    site:
      partitions:
        heading: "État des partitions"
        free_nodes: "Nœuds libres"
        free_cores: "Cœurs libres"
  ```
  Reference those keys in custom ERB partials (`/etc/ood/config/apps/dashboard/views/...`) with `<%= t('site.partitions.heading') %>`.

### Auto-Generating & Synchronizing Missing Locale Files

Open OnDemand includes `OodLocaleConverter` and `AppLocaleSync` to automatically generate missing Dashboard catalogs, `<app>/locales/<locale>.yml` catalogs, and `motd.<locale>` files whenever a new locale or custom app is added:

- **English Regional & Fun Dialects (`en-CA`, `en-GB`, `en-HG`, `en-CP`)**: Generated **100% offline** with deterministic spelling/terminology stylizers while preserving `%{var}` placeholders, Markdown links, HTML tags, code spans, and ERB tags.
- **External Languages (`fr-CA`, EU languages, `ja-JP`, `zh-CN`, `fa-IR`, etc.)**: Generated in batched requests via either Google Cloud Translation API v2 (`GOOGLE_TRANSLATE_API_KEY`) or a self-hosted LibreTranslate endpoint (`OOD_TRANSLATE_URL`), with automatic token protection for `%{var}`, Markdown, HTML, and URLs, plus skip guards so Lmod module versions (e.g., `scipy/2023a`, `afni 23.1.08`) and desktop proper nouns (`GNOME`, `MATE`, `XFCE`, `KDE`) are never mangled.

#### Option A: Root CLI / Cron Sync (Recommended for Production)

Keep translation API credentials root-only so unprivileged user PUNs never read them:

```bash
# /etc/ood/config/translate.env (chmod 0600, chown root:root)
GOOGLE_TRANSLATE_API_KEY="your-api-key-here"
# Or for self-hosted LibreTranslate:
# OOD_TRANSLATE_URL="http://127.0.0.1:5000/translate"
```

Run the idempotent `ensure` task (generates only **missing** Dashboard, app, and MOTD locale files across `supported_locales`):

```bash
cd /var/www/ood/apps/sys/dashboard
OOD_TRANSLATE_ENV_FILE=/etc/ood/config/translate.env \
  MOTD_PATH=/etc/ood/config/ondemand.d/motd \
  RAILS_ENV=production bundle exec rake ood:locales:ensure
```

Available Rake tasks in `apps/dashboard/lib/tasks/app_locales.rake`:

| Task | Purpose |
| --- | --- |
| `rake ood:locales:ensure` | Auto-generates any **missing** Dashboard catalogs (`config/locales/<locale>.yml`), `<app>/locales/<locale>.yml` files, and `motd.<locale>` files for all `supported_locales`. |
| `rake ood:locales:sync_dashboard[locales]` | Fills missing keys in Dashboard `config/locales/<locale>.yml` from `en.yml` (set `FORCE=1` to overwrite). |
| `rake ood:locales:sync_apps[locales]` | Generates or updates `/var/www/ood/apps/sys/*/locales/<locale>.yml` from each app's `manifest.yml` and `form.yml[.erb]`. |
| `rake ood:locales:sync_motd[locales]` | Generates localized `<MOTD_PATH>.<locale>` siblings from `<MOTD_PATH>`. |

#### Option B: Boot-Time Auto-Generation

In single-tenant, container, or development environments where the Dashboard process has write access to `LOCALES_ROOT` / app directories, enable automatic boot-time generation of missing locale files:

```yaml
# /etc/ood/config/ondemand.d/localization.yml
auto_generate_locales: true
```
(Or set `OOD_AUTO_GENERATE_LOCALES=true`.)

### Multi-Login-Node Load-Balanced Deployments

When multiple Open OnDemand login nodes sit behind round-robin DNS or a load balancer without sticky sessions:

1. **Precompile assets once and distribute identical digests** across all login nodes (`RAILS_RELATIVE_URL_ROOT=/pun/sys/dashboard` and `/pun/sys/myjobs`) so CSS/JS/FontAwesome asset hashes match regardless of which node serves a request.
2. **Share `secret_key_base` and use `:cookie_store` per user** across login nodes (for example via an initializer in `/etc/ood/config/apps/{dashboard,myjobs}/initializers/` storing `~/.config/ondemand/pun_secret_key_base` with `0600` permissions on shared `$HOME`) so CSRF tokens remain valid when requests hop between nodes.
3. **Built-in URL & CSRF Resilience**:
   - Navigating directly to `GET /settings` redirects cleanly (`302`) to `/` instead of rendering a routing error.
   - Stale CSRF submissions to `POST /settings` recover gracefully by logging a warning and redirecting back without a `422` error screen.

---

## 3. Multi-Language App Developer Guide

### Application Directory Layout

Any Batch Connect or Passenger app under `/var/www/ood/apps/sys/<app>`, `/var/www/ood/apps/usr/<user>/gateway/<app>`, or `~/ondemand/dev/<app>` can ship per-locale YAML catalogs inside `<app>/locales/`:

```text
my_jupyter_app/
├── manifest.yml
├── form.yml.erb
├── view.html.erb
├── submit.yml.erb
└── locales/
    ├── en-CA.yml
    ├── en-GB.yml
    ├── fr-CA.yml
    ├── de-DE.yml
    └── ...
```

### Localizing `manifest.yml` & `form.yml` Attributes

Keep `manifest.yml` and `form.yml[.erb]` in clean English as the base structural definition, and place translations in `locales/<locale>.yml` under `manifest:` and `form:`:

```yaml
# my_jupyter_app/locales/fr-CA.yml
---
fr-CA:
  manifest:
    name: "JupyterLab"
    description: |
      Lancez un serveur [JupyterLab] interactif sur un nœud de calcul Slurm.

      [JupyterLab]: https://jupyterlab.readthedocs.io/
  form:
    title: "JupyterLab"
    attributes:
      bc_num_hours:
        label: "Nombre d'heures"
        help: "Durée maximale de la session interactive (en heures)."
      num_cores:
        label: "Nombre de cœurs CPU"
        help: "Nombre de cœurs CPU réservés sur le nœud."
      desktop_mode:
        label: "Mode d'interface"
        options:
          lab: "Interface JupyterLab"
          notebook: "Carnet classique"
  view:
    extra_instructions: "Utilisez le terminal intégré pour activer votre environnement Conda."
```

At render time:
- `OodApp#manifest` localizes `manifest.name` and `manifest.description` (preserving Markdown links).
- `BatchConnect::App` localizes `form.title` and each attribute's `label`, `help`, and select/radio `options` (whether options are `[label, value]` pairs or scalar strings, while leaving `data-*` HTML attributes untouched so Dynamic JS directives continue to work).

### Localizing `view.html.erb` Connect Buttons & Session Instructions

Interactive web apps (Jupyter, RStudio, VS Code, OpenRefine, TensorBoard, etc.) define a custom `<app>/view.html.erb` partial rendered on the **My Interactive Sessions** card once the job is running.

Dashboard's `_custom.html.erb` automatically injects three helper variables into the `view.html.erb` binding:
- `app_title`: The session's localized application title (`session.display_title`) in the active `I18n.locale`.
- `session`: The `BatchConnect::Session` instance (`session.app.root` points to the app directory).
- `csp_nonce`: The current Content Security Policy nonce for any inline `<script nonce="<%= csp_nonce %>">` tags.

#### 1. Localizing the Primary "Connect to ..." Button

Replace hardcoded `"Connect to MyApp"` text with `I18n.t('dashboard.batch_connect_sessions_connect_to', app_title: app_title)`:

```erb
<%# my_jupyter_app/view.html.erb %>
<form action="/node/<%= host %>/<%= port %>/login" method="post" target="_blank">
  <input type="hidden" name="password" value="<%= password %>">
  <button class="btn btn-primary" type="submit">
    <i class="fa fa-cogs"></i>
    <%= I18n.t('dashboard.batch_connect_sessions_connect_to',
               app_title: (defined?(app_title) && app_title.present?) ? app_title : 'JupyterLab') %>
  </button>
</form>
```

Because `dashboard.batch_connect_sessions_connect_to` (`"Connect to %{app_title}"`, `"Se connecter à %{app_title}"`, `"Verbinden mit %{app_title}"`, `"Beam Aboard %{app_title}"`, `"Jack Into %{app_title}"`, etc.) is shipped in all 31 Dashboard locales, your app's connect button automatically renders in all 31 languages with zero extra configuration!

#### 2. Localizing Additional Instructions Inside `view.html.erb`

If your `view.html.erb` displays custom helper notes (for example package installation tips in RStudio), add keys under `view:` in `<app>/locales/<locale>.yml` and look them up with `LocalizedValue.app_view_translation`:

```erb
<%
  app_dir = session.app.root if defined?(session) && session&.respond_to?(:app) && session.app&.respond_to?(:root)
  extra_note = LocalizedValue.app_view_translation(
    app_dir,
    'extra_instructions',
    default: 'Use the built-in terminal to activate your Conda environment.'
  )
%>
<p class="mt-2 small text-muted"><%= extra_note %></p>
```

### Localizing App Categories & Subcategories

Dashboard translates standard `manifest.yml` `category` and `subcategory` headers automatically via `dashboard.nav_categories.<slug>` in `apps/dashboard/config/locales/*.yml` (where `<slug>` is `value.strip.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/\A_|_\z/, '')`):

- Built-in slugs localized across all 31 languages include: `files`, `jobs`, `clusters`, `interactive_apps`, `desktops`, `desktop`, `guis`, `servers`, `bioinformatics`, `data_science`, `development`, `machine_learning`, `mathematics`, `utilities`, and `visualization`.
- To add a custom site category (e.g., `category: "Quantum Simulation"` -> slug `quantum_simulation`), add `dashboard.nav_categories.quantum_simulation` in `/etc/ood/config/locales/<locale>.yml`.

### Generating App Locale Files Automatically

After creating or updating an app's `manifest.yml`, `form.yml[.erb]`, or `locales/en-CA.yml` (including any `view:` keys), generate all remaining regional locale catalogs in one command:

```bash
cd /var/www/ood/apps/sys/dashboard
OOD_TRANSLATE_ENV_FILE=/etc/ood/config/translate.env \
  RAILS_ENV=production bundle exec rake ood:locales:sync_apps
```

---

## 4. Contributor & Testing Guide

### Adding or Updating UI Strings

1. Add new English keys to `apps/dashboard/config/locales/en.yml` (and `en-CA.yml`), `apps/myjobs/config/locales/en.yml`, or `apps/shell/locales/en.json`.
   - Place client-side Dashboard JavaScript strings under `dashboard.js.<module>.<key>` so they are automatically exported in `#ood_i18n` and accessible via `t('<module>.<key>')` in `app/javascript/i18n.js`.
2. Propagate translations across all 31 regional locales (either via human translation / Weblate or via `rake ood:locales:sync_dashboard` followed by native review).

### Adding a New Regional or Custom/Themed Locale

1. Register the native display label in `OodLocale::KNOWN_LOCALE_LABELS` (`apps/dashboard/app/lib/ood_locale.rb` and `apps/myjobs/lib/ood_locale.rb`) and `KNOWN_LABELS` (`apps/shell/utils/i18n.js`). If it is a standard selectable regional locale, ensure its tag matches `xx-YY` so `OodLocale.regional_locales` includes it automatically.
2. Add or map its offline DataTables 2.x pack in `apps/dashboard/app/javascript/datatables_i18n.js`.
3. (Optional, for themed/dialect locales like `en-HG` or `en-CP`): Add offline stylizer rules in `OodLocaleConverter` (`apps/dashboard/app/lib/ood_locale_converter.rb`).
4. Generate initial catalogs via `rake ood:locales:ensure` and run the full test suite below.

### Running the Localization Test & CI Suite

```bash
# 1. Dashboard: Zeitwerk, i18n-tasks, LocalesHealthTest, Minitest & Node ESM JS tests
cd apps/dashboard
node --test test/javascript/i18n_test.mjs test/javascript/novnc_localization_test.mjs
bundle exec rails zeitwerk:check
bundle exec i18n-tasks missing --locales en
bundle exec i18n-tasks check-consistent-interpolations
bundle exec rake test

# 2. Job Composer (MyJobs): Locale parity, fallback & controller tests
cd ../myjobs
bundle exec rake test

# 3. Web Shell: Jest i18n & 100% locale JSON parity tests
cd ../shell
yarn test
```
