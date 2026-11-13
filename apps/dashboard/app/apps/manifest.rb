# frozen_string_literal: true

require 'yaml'

# Manifests provide metadata for applications (OodApps).
class Manifest
  include ActiveModel::Model

  attr_reader :exception

  # InvalidContentError is an error helper class to give users a nice
  # error message when there are validation errors.
  class InvalidContentError < StandardError
    def initialize
      super 'Manifest is not formatted correctly!
Manifest should be in YAML format with markdown for description
---
name: Container Fill Sim
description: |
  This is a description.
  With **markdown**.

  And a

  * bullet
    * sub1
    * sub2
  * list

  Support:

  * [Company Website](https://www.osc.edu)

category: OSC
      '
    end
  end

  def self.load(yaml_path)
    if File.exist? yaml_path
      File.open(yaml_path) do |content|
        Manifest.new(YAML.safe_load(content)).tap { |m| m.send(:manifest_path=, yaml_path) }
      end
    else
      MissingManifest.new(yaml_path)
    end
  rescue StandardError => e
    Rails.logger.warn "Cannot load manifest: #{yaml_path} with error #{e.class}: #{e.message}"
    InvalidManifest.new(e)
  end

  def self.load_from_string(yaml)
    Manifest.new(YAML.safe_load(yaml))
  rescue StandardError => e
    Rails.logger.warn "Cannot load manifest from string with error #{e.class}: #{e.message}"
    InvalidManifest.new(e)
  end

  # @param [Hash, Manifest] opts A hash of the options in the manifest.
  # @option opts [String, Hash] :name The name of the application.
  # @option opts [String, Hash] :description The description of the application.
  # @option opts [String, Hash] :category The category of the application.
  # @option opts [String, Hash] :subcategory The subcategory of the application.
  # @option opts [String] :icon The icon used on the dashboard, optionally a Font Awesome tag.
  # @option opts [String] :role Dashboard categorization.
  # @option opts [String, Hash] :url An optional redirect URL.
  # @option opts [Hash]   :metadata An optional hash of key value pairs.
  # @option opts [Hash]   :tile An optional hash of key value pairs.
  def initialize(opts)
    raise InvalidContentError unless opts&.respond_to?(:to_h)

    @manifest_options = opts.to_h.with_indifferent_access.select do |method, _val|
      respond_to?(method) && !%w[default_category default_subcategory].include?(method.to_s)
    end
  end

  # The name of the application
  #
  # @return [String] name as string
  def name
    manifest_field(:name)
  end

  # The description of the application
  #
  # @return [String] description as string
  def description
    manifest_field(:description)
  end

  # The icon used on the dashboard, optionally a Font Awesome tag
  #
  # @return [String] icon as string
  def icon
    @manifest_options[:icon] || ''
  end

  # Return the optional redirect URL string
  #
  # @return [String] url as string
  def url
    manifest_field(:url)
  end

  # Return the app category
  #
  # @return [String] category as string
  def category
    manifest_field(:category)
  end

  # Canonical default-locale category used for cross-locale token/nav matching
  def default_category
    manifest_field(:category, locale: :en)
  end

  # Return the app subcategory
  #
  # @return [String] subcategory as string
  def subcategory
    manifest_field(:subcategory)
  end

  # Canonical default-locale subcategory used for cross-locale token/nav matching
  def default_subcategory
    manifest_field(:subcategory, locale: :en)
  end

  # Return the app role
  #
  # @return [String] role as string
  def role
    @manifest_options[:role] || ''
  end

  # Return the app metadata
  #
  # @return [Hash] metadata as a hash
  def metadata
    @manifest_options[:metadata] || {}
  end

  # Return the app's hint of whether to open app in new window
  #
  # @return [Boolean, nil] if set, Boolean value, otherwise nil
  def new_window
    @manifest_options[:new_window]
  end

  # Return the app's caption
  #
  #  @return [String] caption as string
  def caption
    manifest_field(:caption)
  end

  # Return the app's tile data. Used to render the pinned app tile
  #
  #  @return [Hash] icon as hash
  def tile
    base_tile = (@manifest_options[:tile] || {}).to_h
    i18n_tile = app_manifest_translations[:tile]
    merged = i18n_tile.is_a?(Hash) ? base_tile.deep_symbolize_keys.merge(i18n_tile) : base_tile
    merged.empty? ? {} : LocalizedValue.resolve_tile_hash(merged)
  end

  # Manifest objects are valid
  #
  # @return [true] Always return true
  def valid?
    true
  end

  # Manifest objects exist
  #
  # @return [true] Always return true
  def exist?
    true
  end

  # Save the current manifest to a path.
  #
  # @param [String, Pathname] path The full path of the file to be saved as string or Pathname object
  #
  # @return [true, false] true if the file is saved successfully
  def save(path)
    Pathname.new(path).write(to_yaml)

    true
  rescue StandardError => e
    @exception = e
    errors.add(:save, e.message)
    Rails.logger.warn "Cannot save manifest: #{path} with error #{e.class}:#{e.message}"
    false
  end

  # Merge the contents of a hash into this Manifest's options
  #
  # @param [Hash, Manifest] opts The options to update
  #
  # @return [Manifest] A new manifest with the updated options
  def merge(opts)
    raise InvalidContentError unless opts&.respond_to?(:to_h)

    Manifest.new(@manifest_options.merge(opts.to_h)).tap { |m| m.send(:manifest_path=, @manifest_path) }
  end

  private

  def manifest_path=(yaml_path)
    @manifest_path = yaml_path ? Pathname.new(yaml_path.to_s) : nil
    @app_root = @manifest_path&.dirname
  end

  def manifest_field(field, locale: I18n.locale)
    i18n_val = app_manifest_translations(locale: locale)[field]
    return LocalizedValue.resolve(i18n_val, locale: locale) unless i18n_val.nil?

    LocalizedValue.resolve(@manifest_options[field], locale: locale)
  end

  def app_manifest_translations(locale: I18n.locale)
    return {} unless @app_root

    @app_manifest_translations_by_locale ||= {}
    key = locale.to_s
    @app_manifest_translations_by_locale[key] ||= begin
      catalog = LocalizedValue.app_translations(@app_root, locale: locale)
      catalog[:manifest].is_a?(Hash) ? catalog[:manifest] : {}
    end
  end

  public

  # Creates a hash of the object's current state.
  #
  # @return [Hash] A hash representation of the Manifest object.
  def to_h
    @manifest_options.to_h
  end

  # Returns the contents of the object as a YAML string with the empty values removed.
  #
  # @return [String] The populated contents of the object as YAML string.
  def to_yaml
    to_h.deep_stringify_keys.compact.to_yaml
  end

  class InvalidManifest < Manifest
    def initialize(exception)
      super({})

      @exception = exception
      errors.add(:load, exception.message)
    end

    def valid?
      false
    end

    def save(_path)
      false
    end
  end

  class MissingManifest < Manifest
    def initialize(yaml_path = nil)
      super({})

      errors.add(:load, "Manifest not found at #{yaml_path}") if yaml_path
    end

    def valid?
      false
    end

    def exist?
      false
    end

    def save(_path)
      false
    end
  end
end
