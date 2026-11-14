require 'test_helper'

class MotdFileTest < ActiveSupport::TestCase

  test "test when motd file_valid" do

    path = "#{Rails.root}/test/fixtures/files/motd_valid"
    motd_file = MotdFile.new(path)
    expected_file = File.open(path).read

    assert_equal true, motd_file.exist?
    assert_equal path, motd_file.motd_path
    assert_equal expected_file, motd_file.content
  end

  test "test when motd file_empty" do
    path = "#{Rails.root}/test/fixtures/files/motd_empty"
    motd_file = MotdFile.new(path)

    assert_equal true, motd_file.exist?
    assert_equal path, motd_file.motd_path
    assert_equal '', motd_file.content
  end

  test "test when motd file_missing" do
    path = "#{Rails.root}/test/fixtures/files/motd_missing"
    motd_file = MotdFile.new(path)

    assert_equal false, motd_file.exist?
    assert_equal path, motd_file.motd_path
    assert_equal '', motd_file.content
  end

  test "test when motd file_nil" do

    motd_file = MotdFile.new(nil)

    assert_equal false, motd_file.exist?
    assert_nil motd_file.motd_path
    assert_equal '', motd_file.content
  end

  test 'when MOTD_PATH is unset, a default formatter is returned' do
    with_modified_env({ 'MOTD_PATH' => nil }) do
      formatter = MotdFile.new.formatter
      assert_instance_of(MotdFormatter::Default, formatter)
      assert_equal(I18n.t('dashboard.motd_title'), formatter.title)
      assert_not_empty(formatter.content.to_s)
    end
  end

  test 'when MOTD_PATH is explicitly blank, no formatter is returned' do
    with_modified_env({ 'MOTD_PATH' => '' }) do
      formatter = MotdFile.new.formatter
      assert_nil(formatter)
    end
  end
  
  test 'when rss is a remote source' do
    with_modified_env({ MOTD_PATH: 'https://www.osc.edu/rss.xml', MOTD_FORMAT: 'rss' }) do
      formatter = MotdFile.new.formatter
      assert_not_nil(formatter.title)
      assert_not_nil(formatter.content)
      assert_not_nil(formatter.content.items)
    end
  end

  test 'resolves per-language sibling MOTD files and falls back to base motd' do
    Dir.mktmpdir do |dir|
      base = File.join(dir, 'motd')
      fr   = File.join(dir, 'motd.fr-CA')
      File.write(base, 'Welcome to the cluster')
      File.write(fr, 'Bienvenue sur la grappe')

      assert_equal 'Welcome to the cluster', MotdFile.new(base, locale: :en).content
      assert_equal 'Bienvenue sur la grappe', MotdFile.new(base, locale: :'fr-CA').content
      assert_equal 'Bienvenue sur la grappe', MotdFile.new(base, locale: :fr).content
      assert_equal 'Welcome to the cluster', MotdFile.new(base, locale: :ja_JP).content
    end
  end

  test 'resolves extension-preserving and directory-style localized MOTD files across formats' do
    Dir.mktmpdir do |dir|
      md_base = File.join(dir, 'motd.md')
      md_fr   = File.join(dir, 'motd.fr-CA.md')
      File.write(md_base, '# English Heading')
      File.write(md_fr, '# Titre français')

      with_modified_env({ 'MOTD_FORMAT' => 'markdown' }) do
        formatter = MotdFile.new(md_base, locale: :'fr-CA').formatter
        assert_instance_of MotdFormatter::Markdown, formatter
        assert_match(/Titre français/, formatter.content)
      end

      sub_dir = File.join(dir, 'motd_dir')
      Dir.mkdir(sub_dir)
      File.write(File.join(sub_dir, 'motd'), 'Default dir MOTD')
      File.write(File.join(sub_dir, 'fr-CA'), 'MOTD répertoire français')

      assert_equal 'Default dir MOTD', MotdFile.new(sub_dir, locale: :en).content
      assert_equal 'MOTD répertoire français', MotdFile.new(sub_dir, locale: :'fr-CA').content
    end
  end

  test 'title supports localized motd_title configuration map' do
    Configuration.stubs(:config).returns({ motd_title: { en: 'Cluster News', 'fr-CA': 'Nouvelles de la grappe' } })
    with_modified_env({ 'MOTD_TITLE' => nil }) do
      assert_equal 'Cluster News', MotdFile.new(nil, locale: :en).title
      assert_equal 'Nouvelles de la grappe', MotdFile.new(nil, locale: :'fr-CA').title
    end
  end

end
