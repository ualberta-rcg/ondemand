require 'test_helper'

class AppRouterTest < ActiveSupport::TestCase
  test "DevRouter.apps" do
    dir = Pathname.new(File.realpath(Dir.mktmpdir))
    DevRouter.stubs(:base_path).returns(dir)
    %w(a b c .git).each {|d| dir.join(d).mkdir }
    FileUtils.touch dir.join("d.txt").to_s
    dir.join("c").chmod(0600)
    dir.join("d.txt").chmod(0700)

    assert_equal ["a", "b"].sort, DevRouter.apps.map(&:name).sort

    dir.rmtree()
  end

  test "SysRouter.apps should hide apps that have periods in directory name" do
    Dir.mktmpdir "apps" do |dir|
      dir = Pathname.new(dir)
      [
        "app1",
        ".app2",
        "app-3",
        "app.4"
      ].each { |d| dir.join(d).mkdir }

      SysRouter.stubs(:base_path).returns(dir)

      apps = SysRouter.apps.map(&:name).sort
      assert_equal ["app1", "app-3"].sort, apps
    end
  end

  test "UsrRouter.apps should hide apps that have periods in directory name" do
    Dir.mktmpdir "apps" do |dir|
      dir = Pathname.new(dir)
      [
        "app1",
        ".app2",
        "app-3",
        "app.4"
      ].each { |d| dir.join(d).mkdir }

      UsrRouter.stubs(:base_path).returns(dir)

      apps = UsrRouter.apps.map(&:name).sort
      assert_equal ["app1", "app-3"].sort, apps
    end
  end

  test "UsrRouter.caption when user is a group (or non-existance user)" do
    assert_equal "Shared by PZS0714", UsrRouter.new('foo', 'PZS0714').caption
  end

  test "DevRouter.apps should only apps that have periods in directory name" do
    Dir.mktmpdir "apps" do |dir|
      dir = Pathname.new(dir)
      [
        "app1",
        ".app2",
        "app-3",
        "app.4"
      ].each { |d| dir.join(d).mkdir }

      DevRouter.stubs(:base_path).returns(dir)

      apps = DevRouter.apps.map(&:name).sort
      assert_equal ["app1", "app-3"].sort, apps
    end
  end

  test "SysRouter and DevRouter evaluate captions and categories dynamically for active locale" do
    sys_router = I18n.with_locale(:en) { SysRouter.new('jupyter') }
    dev_router = I18n.with_locale(:en) { DevRouter.new('jupyter', 'me') }

    I18n.with_locale(:en) do
      assert_equal I18n.t('dashboard.system_apps_caption', locale: :en), sys_router.caption
      assert_equal I18n.t('dashboard.development_apps_caption', locale: :en), dev_router.caption
      assert_equal I18n.t('dashboard.development_apps_category', locale: :en), dev_router.category
    end

    I18n.with_locale(:'fr-CA') do
      assert_equal I18n.t('dashboard.system_apps_caption', locale: :'fr-CA'), sys_router.caption
      assert_equal I18n.t('dashboard.development_apps_caption', locale: :'fr-CA'), dev_router.caption
      assert_equal I18n.t('dashboard.development_apps_category', locale: :'fr-CA'), dev_router.category
    end
  end

  test "SysRouter.apps, DevRouter.apps, and UsrRouter.apps isolate cache entries per locale" do
    Dir.mktmpdir "apps" do |dir|
      app_root = Pathname.new(dir)
      bc_dir = app_root.join('bc_loc')
      bc_dir.mkdir
      bc_dir.join('manifest.yml').write("---\nrole: batch_connect\n")
      bc_dir.join('form.yml.erb').write("---\ntitle: \"App-<%= I18n.locale %>\"\ncluster: 'oakley'\n")

      SysRouter.stubs(:base_path).returns(app_root)
      DevRouter.stubs(:base_path).returns(app_root)
      UsrRouter.stubs(:base_path).returns(app_root)
      mem_cache = ActiveSupport::Cache::MemoryStore.new
      Rails.stubs(:cache).returns(mem_cache)

      assert_equal 'App-en', I18n.with_locale(:en) { SysRouter.apps.first.title }
      assert_equal 'App-fr-CA', I18n.with_locale(:'fr-CA') { SysRouter.apps.first.title }

      assert_equal 'App-en', I18n.with_locale(:en) { DevRouter.apps(owner: 'me').first.title }
      assert_equal 'App-fr-CA', I18n.with_locale(:'fr-CA') { DevRouter.apps(owner: 'me').first.title }

      assert_equal 'App-en', I18n.with_locale(:en) { UsrRouter.apps(owner: 'me').first.title }
      assert_equal 'App-fr-CA', I18n.with_locale(:'fr-CA') { UsrRouter.apps(owner: 'me').first.title }
    end
  end
end
