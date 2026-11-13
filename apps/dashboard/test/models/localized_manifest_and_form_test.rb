# frozen_string_literal: true

require 'test_helper'

class LocalizedManifestAndFormTest < ActiveSupport::TestCase
  setup do
    OodAppkit.stubs(:clusters).returns(OodCore::Clusters.load_file('test/fixtures/config/clusters.d'))
    Router.instance_variable_set(:@pinned_apps, nil)
  end

  teardown do
    I18n.locale = :en
    Router.instance_variable_set(:@pinned_apps, nil)
  end

  test 'LocalizedValue distinguishes locale hashes from ordinary config hashes' do
    assert LocalizedValue.locale_hash?({ en: 'Desktop', 'fr-CA': 'Bureau', ja_JP: 'デスクトップ' })
    refute LocalizedValue.locale_hash?({ min: 1, max: 10 })
    refute LocalizedValue.locale_hash?({ id: '1', url: '/foo' })
    refute LocalizedValue.locale_hash?({ title: 'Desktop', icon: 'fas://desktop' })
    refute LocalizedValue.locale_hash?({})
  end

  test 'LocalizedValue resolves exact, primary prefix, regional sibling, and English fallback' do
    val = { en: 'Desktop', 'fr-CA': 'Bureau canadien' }

    assert_equal 'Desktop', LocalizedValue.resolve(val, locale: :en)
    assert_equal 'Desktop', LocalizedValue.resolve(val, locale: :'en-CA')
    assert_equal 'Bureau canadien', LocalizedValue.resolve(val, locale: :'fr-CA')
    assert_equal 'Bureau canadien', LocalizedValue.resolve(val, locale: :fr)
    assert_equal 'Bureau canadien', LocalizedValue.resolve(val, locale: :'fr-FR')
    assert_equal 'Desktop', LocalizedValue.resolve(val, locale: :'ja-JP')
  end

  test 'Manifest resolves inline locale hashes while preserving raw YAML options on save' do
    opts = {
      name:        { 'en' => 'Bio Portal', 'fr-CA' => 'Portail Bio' },
      description: { 'en' => 'English desc', 'fr-CA' => 'Description française' },
      category:    { 'en' => 'Bioinformatics', 'fr-CA' => 'Bio-informatique' },
      subcategory: { 'en' => 'Genomics', 'fr-CA' => 'Génomique' },
      caption:     { 'en' => 'v1', 'fr-CA' => 'v1 (FR)' },
      tile:        { 'sub_caption' => { 'en' => 'Fast node', 'fr-CA' => 'Nœud rapide' } }
    }
    manifest = Manifest.new(opts)

    I18n.with_locale(:en) do
      assert_equal 'Bio Portal', manifest.name
      assert_equal 'English desc', manifest.description
      assert_equal 'Bioinformatics', manifest.category
      assert_equal 'Genomics', manifest.subcategory
      assert_equal 'v1', manifest.caption
      assert_equal 'Fast node', manifest.tile[:sub_caption]
    end

    I18n.with_locale(:'fr-CA') do
      assert_equal 'Portail Bio', manifest.name
      assert_equal 'Description française', manifest.description
      assert_equal 'Bio-informatique', manifest.category
      assert_equal 'Génomique', manifest.subcategory
      assert_equal 'Bioinformatics', manifest.default_category
      assert_equal 'Genomics', manifest.default_subcategory
      assert_equal 'v1 (FR)', manifest.caption
      assert_equal 'Nœud rapide', manifest.tile[:sub_caption]
    end

    assert_equal({ 'en' => 'Bio Portal', 'fr-CA' => 'Portail Bio' }, manifest.to_h['name'])
  end

  test 'Built-in OOD apps load per-app locales/*.yml catalogs across locales' do
    activejobs_manifest = Manifest.load(Rails.root.join('../activejobs/manifest.yml'))
    bc_desktop_router = PathRouter.new(Rails.root.join('../bc_desktop'))

    I18n.with_locale(:en) do
      assert_equal 'Active Jobs', activejobs_manifest.name
      app = BatchConnect::App.new(router: bc_desktop_router)
      assert_equal 'Desktop', app.title
      desktop_attr = app.attributes.find { |a| a.id == 'desktop' }
      assert_equal 'Desktop Environment', desktop_attr.label
      assert_includes desktop_attr.select_choices, ['GNOME', 'gnome']
    end

    I18n.with_locale(:'fr-CA') do
      assert_equal 'Tâches actives', activejobs_manifest.name
      app = BatchConnect::App.new(router: bc_desktop_router)
      assert_equal 'Bureau interactif', app.title
      desktop_attr = app.attributes.find { |a| a.id == 'desktop' }
      assert_equal 'Environnement de bureau', desktop_attr.label
      assert_includes desktop_attr.select_choices, ['GNOME', 'gnome']
    end
  end

  test 'BatchConnect::App supports both inline locale hashes and per-app locales/*.yml with sub-apps' do
    Dir.mktmpdir do |dir|
      root = Pathname.new(dir)
      root.join('manifest.yml').write("---\nname: Jupyter\ncategory: Interactive Apps\nsubcategory: Servers\nrole: batch_connect\n")
      root.join('form.yml').write(<<~YAML)
        ---
        cluster:
          - owens
        form:
          - bc_num_hours
          - node_size
        attributes:
          bc_num_hours:
            label:
              en: "Walltime (Hours)"
              fr-CA: "Durée maximale (heures)"
            help:
              en: "Max 24h"
              fr-CA: "Maximum 24 h"
            header:
              en: "Resources"
              fr-CA: "Ressources"
          node_size:
            widget: select
            options:
              - [ { en: "Small Node", fr-CA: "Petit nœud" }, "small", data-set-cores: 4 ]
              - [ "Large Node", "large" ]
      YAML

      root.join('local').mkdir
      root.join('local/gpu.yml').write("---\ncluster:\n  - owens\nform:\n  - node_size\nattributes:\n  node_size:\n    widget: select\n    options:\n      - [ \"Large Node\", \"large\" ]\n")

      root.join('locales').mkdir
      root.join('locales/fr-CA.yml').write(<<~YAML)
        ---
        fr-CA:
          form:
            title: "Carnet Jupyter"
            sub_apps:
              gpu:
                title: "Carnet Jupyter (GPU)"
            attributes:
              node_size:
                label: "Taille du nœud"
                options:
                  large: "Grand nœud"
      YAML

      router = PathRouter.new(root)
      app = BatchConnect::App.new(router: router)
      sub_app = BatchConnect::App.new(router: router, sub_app: 'gpu')

      I18n.with_locale(:en) do
        assert_equal 'Jupyter', app.title
        hours = app.attributes.find { |a| a.id == 'bc_num_hours' }
        assert_equal 'Walltime (Hours)', hours.label
        assert_equal 'Max 24h', hours.help
        assert_equal 'Resources', hours.header
        refute hours.field_options.key?(:header)

        size = app.attributes.find { |a| a.id == 'node_size' }
        assert_equal ['Small Node', 'small', { 'data-set-cores': 4 }], size.select_choices.first
        assert_equal ['Large Node', 'large'], size.select_choices.second
      end

      I18n.with_locale(:'fr-CA') do
        assert_equal 'Carnet Jupyter', app.title
        assert_equal 'Carnet Jupyter (GPU)', sub_app.title

        hours = app.attributes.find { |a| a.id == 'bc_num_hours' }
        assert_equal 'Durée maximale (heures)', hours.label
        assert_equal 'Maximum 24 h', hours.help
        assert_equal 'Ressources', hours.header

        size = app.attributes.find { |a| a.id == 'node_size' }
        assert_equal 'Taille du nœud', size.label
        assert_equal ['Petit nœud', 'small', { 'data-set-cores': 4 }], size.select_choices.first
        assert_equal ['Grand nœud', 'large'], size.select_choices.second
      end
    end
  end

  test 'OodAppGroup, TokenMatcher, and Router.pinned_apps translate categories and isolate caches per locale' do
    Dir.mktmpdir do |dir|
      app_dir = Pathname.new(dir).join('bio_app')
      app_dir.mkdir
      app_dir.join('manifest.yml').write(<<~YAML)
        ---
        name:
          en: "Genome Viewer"
          fr-CA: "Visualiseur de génome"
        category:
          en: "Interactive Apps"
          fr-CA: "Applications interactives"
        subcategory:
          en: "Servers"
          fr-CA: "Serveurs"
        url: "/pun/sys/bio"
      YAML

      ood_app = OodApp.new(PathRouter.new(app_dir))
      tokens = [{ category: 'Interactive Apps', subcategory: 'Servers' }]

      en_pinned = I18n.with_locale(:en) { Router.pinned_apps(tokens, [ood_app]) }
      fr_pinned = I18n.with_locale(:'fr-CA') do
        groups = OodAppGroup.groups_for(apps: [ood_app])
        selected = OodAppGroup.select(titles: ['Interactive Apps'], groups: groups)
        assert_equal 1, selected.size
        assert_equal 'Applications interactives', selected.first.localized_title

        Router.pinned_apps(tokens, [ood_app])
      end

      assert_equal 1, en_pinned.size
      assert_equal 1, fr_pinned.size
      I18n.with_locale(:en) { assert_equal 'Genome Viewer', en_pinned.first.links.first.title }
      I18n.with_locale(:'fr-CA') { assert_equal 'Visualiseur de génome', fr_pinned.first.links.first.title }
    end
  end

  test 'OodAppLink resolves localized title, description, and locale-specific documentation URL' do
    cfg = {
      title:       { en: 'Cluster Docs', 'fr-CA': 'Documentation de la grappe' },
      description: { en: 'User guide', 'fr-CA': 'Guide utilisateur' },
      url:         { en: 'https://example.edu/docs/en', 'fr-CA': 'https://example.edu/docs/fr' }
    }

    I18n.with_locale(:en) do
      link = OodAppLink.new(cfg)
      assert_equal 'Cluster Docs', link.title
      assert_equal 'https://example.edu/docs/en', link.url
    end

    I18n.with_locale(:'fr-CA') do
      link = OodAppLink.new(cfg)
      assert_equal 'Documentation de la grappe', link.title
      assert_equal 'https://example.edu/docs/fr', link.url
    end
  end
end
