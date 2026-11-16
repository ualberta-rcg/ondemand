# frozen_string_literal: true

require 'cgi'
require 'json'
require 'net/http'
require 'uri'

# Admin CLI & auto-generation helper for converting Open OnDemand YAML catalogs,
# app manifests/forms, and MOTD files into static on-disk locale files
# (`config/locales/<locale>.yml`, `<app>/locales/<locale>.yml`, and `motd.<locale>`).
class OodLocaleConverter
  TOKEN_PREFIX = '__OODTOK'
  TOKEN_SUFFIX = '__'
  DEFAULT_TRANSLATE_ENV = 'translate.env'
  OFFLINE_STYLED_LOCALES = %w[en-gb en-hg en-cp].freeze

  EN_GB_SPELLINGS = [
    [/\bCanceled\b/, 'Cancelled'],
    [/\bcanceled\b/, 'cancelled'],
    [/\bCanceling\b/, 'Cancelling'],
    [/\bcanceling\b/, 'cancelling'],
    [/\bFavorites\b/, 'Favourites'],
    [/\bfavorites\b/, 'favourites'],
    [/\bFavorite\b/, 'Favourite'],
    [/\bfavorite\b/, 'favourite'],
    [/\bInitialize\b/, 'Initialise'],
    [/\binitialize\b/, 'initialise'],
    [/\bInitializing\b/, 'Initialising'],
    [/\binitializing\b/, 'initialising'],
    [/\bInitialized\b/, 'Initialised'],
    [/\binitialized\b/, 'initialised'],
    [/\bCustomize\b/, 'Customise'],
    [/\bcustomize\b/, 'customise'],
    [/\bCustomizing\b/, 'Customising'],
    [/\bcustomizing\b/, 'customising'],
    [/\bSynchronize\b/, 'Synchronise'],
    [/\bsynchronize\b/, 'synchronise'],
    [/\bOrganization\b/, 'Organisation'],
    [/\borganization\b/, 'organisation'],
    [/\bColor\b/, 'Colour'],
    [/\bcolor\b/, 'colour'],
    [/\bBehavior\b/, 'Behaviour'],
    [/\bbehavior\b/, 'behaviour'],
    [/\bAnalyze\b/, 'Analyse'],
    [/\banalyze\b/, 'analyse']
  ].freeze

  EN_HG_TERMS = [
    [/\bSupport Ticket\b/, 'Sub-Etha Distress Flare'],
    [/\bsupport ticket\b/, 'Sub-Etha distress flare'],
    [/\bInteractive Apps\b/, 'Improbability Engines'],
    [/\bInteractive Desktop\b/, 'Heart of Gold Bridge'],
    [/\bActive Jobs\b/, 'Deep Thought Computations'],
    [/\bJob Composer\b/, 'Computation Composer'],
    [/\bMy Interactive Sessions\b/, 'Active Improbability Voyages'],
    [/\bClusters\b/, 'Galactic Sectors'],
    [/\bCluster\b/, 'Galactic Sector'],
    [/\bcluster\b/, 'galactic sector'],
    [/\bShell Access\b/, 'Sub-Etha Terminal'],
    [/\bFiles\b/, 'Guide Entries'],
    [/\bDashboard\b/, 'The Guide'],
    [/\bLog Out\b/, 'So Long & Thanks'],
    [/\bLaunch\b/, 'Engage Improbability Drive:'],
    [/\bConnect to\b/, 'Beam Aboard'],
    [/\bSubmit\b/, 'Transmit (42)'],
    [/\bDelete\b/, 'Vogon-Demolish'],
    [/\bCancel\b/, 'Abort Trajectory'],
    [/\bError\b/, 'Mildly Alarming Improbability'],
    [/\bWarning\b/, "Don't Panic"],
    [/\bLoading\b/, 'Consulting Deep Thought'],
    [/\bRunning\b/, 'Computing 42'],
    [/\bQueued\b/, 'In Vogon Queue'],
    [/\bCompleted\b/, 'Mostly Harmless (Done)']
  ].freeze

  EN_CP_TERMS = [
    [/\bSupport Ticket\b/, 'Fixer Trauma Ping'],
    [/\bsupport ticket\b/, 'Fixer trauma ping'],
    [/\bInteractive Apps\b/, 'Cyberdeck Daemons'],
    [/\bInteractive Desktop\b/, 'Netrunner Rig'],
    [/\bActive Jobs\b/, 'Live Icebreakers'],
    [/\bJob Composer\b/, 'Daemon Compiler'],
    [/\bMy Interactive Sessions\b/, 'Active Netdives'],
    [/\bClusters\b/, 'Mainframe Subnets'],
    [/\bCluster\b/, 'Subnet'],
    [/\bcluster\b/, 'subnet'],
    [/\bShell Access\b/, 'Black-ICE Console'],
    [/\bFiles\b/, 'Datashards'],
    [/\bDashboard\b/, 'Cyberdeck HUD'],
    [/\bLog Out\b/, 'Jack Out'],
    [/\bLaunch\b/, 'Breach & Spin Up'],
    [/\bConnect to\b/, 'Jack Into'],
    [/\bSubmit\b/, 'Upload Daemon'],
    [/\bDelete\b/, 'Flatline'],
    [/\bCancel\b/, 'Zero Out'],
    [/\bError\b/, 'Black-ICE Glitch'],
    [/\bWarning\b/, 'Relic Malfunction'],
    [/\bLoading\b/, 'Jacking In'],
    [/\bRunning\b/, 'Burning Chrome'],
    [/\bQueued\b/, 'Staged in Buffer'],
    [/\bCompleted\b/, 'Preem (Done)']
  ].freeze

  def self.load_translate_env(path = nil)
    env_file = path.presence || ENV['OOD_TRANSLATE_ENV_FILE'].presence || default_translate_env_path
    return {} unless env_file && File.file?(env_file) && File.readable?(env_file)

    if defined?(Dotenv)
      Dotenv.parse(env_file)
    else
      parse_simple_env(env_file)
    end
  rescue StandardError
    {}
  end

  def self.default_translate_env_path
    candidates = []
    candidates << File.join(Configuration.config_root.to_s, DEFAULT_TRANSLATE_ENV) if defined?(Configuration) && Configuration.respond_to?(:config_root)
    candidates << File.join(Configuration.config_directory.to_s, DEFAULT_TRANSLATE_ENV) if defined?(Configuration) && Configuration.respond_to?(:config_directory)
    candidates << "/etc/ood/config/#{DEFAULT_TRANSLATE_ENV}"
    candidates.uniq.find { |p| File.file?(p) && File.readable?(p) } || candidates.first
  end

  def self.parse_simple_env(file)
    File.readlines(file, chomp: true).each_with_object({}) do |line, acc|
      stripped = line.strip
      next if stripped.empty? || stripped.start_with?('#')

      stripped = stripped.sub(/\Aexport\s+/, '')
      key, val = stripped.split('=', 2)
      next unless key && val

      acc[key.strip] = val.strip.gsub(/\A['"]|['"]\z/, '')
    end
  end

  def initialize(
    google_api_key: nil,
    translate_url:  nil,
    translator:     nil,
    env_file:       nil
  )
    file_vars = (google_api_key.nil? && translate_url.nil? && translator.nil?) ? self.class.load_translate_env(env_file) : {}
    @google_api_key = (google_api_key.nil? ? (ENV['GOOGLE_TRANSLATE_API_KEY'] || file_vars['GOOGLE_TRANSLATE_API_KEY']) : google_api_key).to_s.strip
    @translate_url  = (translate_url.nil? ? (ENV['OOD_TRANSLATE_URL'] || file_vars['OOD_TRANSLATE_URL']) : translate_url).to_s.strip
    @translator     = translator
  end

  def available?
    !@translator.nil? || !@google_api_key.empty? || !@translate_url.empty?
  end

  def offline_styled_locale?(target_locale)
    OFFLINE_STYLED_LOCALES.include?(target_locale.to_s.tr('_', '-').downcase)
  end

  def available_for?(target_locale)
    offline_styled_locale?(target_locale) || available?
  end

  # Convert a Markdown, ERB, HTML, or plain string while preserving fenced/inline
  # code, ERB `<% ... %>` tags, HTML tags, `%{var}` interpolations, and link URLs.
  def convert_text(text, target_locale:, source_locale: 'en')
    return text if text.nil? || !available_for?(target_locale)

    str = text.to_s
    return str if str.strip.empty?
    return str if same_unmodified_language?(source_locale, target_locale)

    working, tokens = protect_tokens(str, target_locale: target_locale, source_locale: source_locale)
    translated = translate_raw(working, target_locale: target_locale, source_locale: source_locale)
    return str if translated.nil?

    restore_tokens(translated, tokens)
  end

  # Batch-convert an Array of strings, preserving all placeholders and HTML/code tokens.
  def convert_texts(texts, target_locale:, source_locale: 'en', batch_size: 80)
    list = Array(texts)
    return list if list.empty? || !available_for?(target_locale)
    return list.map(&:to_s) if same_unmodified_language?(source_locale, target_locale)

    if offline_styled_locale?(target_locale) || @translator || !@translate_url.empty?
      return list.map { |t| convert_text(t, target_locale: target_locale, source_locale: source_locale) }
    end

    prepared = list.map do |item|
      s = item.to_s
      if s.strip.empty?
        [s, nil, []]
      else
        working, toks = protect_tokens(s, target_locale: target_locale, source_locale: source_locale, translate_links: false)
        [s, working, toks]
      end
    end

    results = Array.new(prepared.size)
    non_empty_indices = prepared.each_index.select { |i| !prepared[i][1].nil? }

    non_empty_indices.each_slice(batch_size) do |slice_idxs|
      batch_inputs = slice_idxs.map { |i| prepared[i][1] }
      batch_outputs = translate_batch_via_google(batch_inputs, target_locale: target_locale, source_locale: source_locale)
      slice_idxs.each_with_index do |orig_idx, pos|
        orig_str, _working, toks = prepared[orig_idx]
        raw_out = batch_outputs && batch_outputs[pos]
        results[orig_idx] = raw_out ? restore_tokens(raw_out, toks) : orig_str
      end
    end

    prepared.each_index do |i|
      results[i] = prepared[i][0] if results[i].nil?
    end
    results
  end

  # Convert MOTD content while preserving all 6 Open OnDemand MOTD formats:
  # `plaintext`, `markdown`, `markdown_erb`, `text_erb`, `osc`, and `rss`.
  def convert_motd(content, target_locale:, source_locale: 'en', format: ENV['MOTD_FORMAT'])
    return content if content.nil? || !available_for?(target_locale)

    case format.to_s.strip.downcase
    when 'osc'
      convert_osc_motd(content, target_locale: target_locale, source_locale: source_locale)
    when 'rss'
      convert_rss_motd(content, target_locale: target_locale, source_locale: source_locale)
    else
      convert_text(content, target_locale: target_locale, source_locale: source_locale)
    end
  end

  private

  def protect_tokens(str, target_locale:, source_locale:, translate_links: true)
    tokens = []
    stash = lambda do |raw|
      idx = tokens.length
      tokens << raw
      "#{TOKEN_PREFIX}#{idx}#{TOKEN_SUFFIX}"
    end

    working = str.dup
    working.gsub!(/(?:```[\s\S]*?```|~~~[\s\S]*?~~~)/) { |m| stash.call(m) }
    working.gsub!(/<%[\s\S]*?%>/) { |m| stash.call(m) }
    working.gsub!(/`[^`\n]+`/) { |m| stash.call(m) }

    ref_ids = []
    working.gsub!(/^(\s*\[([^\[\]\n]+)\]:\s*\S+[^\n]*)/) do
      full_def = Regexp.last_match(1)
      ref_ids << Regexp.last_match(2)
      stash.call(full_def)
    end
    ref_ids.uniq.each do |ref_id|
      working.gsub!(/\[#{Regexp.escape(ref_id)}\](?![\(\[:])/) do
        if translate_links
          translated_label = translate_protected_segment(ref_id, target_locale: target_locale, source_locale: source_locale)
          translated_label == ref_id ? stash.call("[#{ref_id}]") : stash.call("[#{translated_label}][#{ref_id}]")
        else
          stash.call("[#{ref_id}]")
        end
      end
    end

    working.gsub!(/\[([^\[\]\n]+)\](\([^\)\s]+(?:\s+"[^"]*")?\))/) do
      label = Regexp.last_match(1)
      url_part = Regexp.last_match(2)
      if !translate_links || label.match?(%r{\Ahttps?://}i) || label.include?(TOKEN_PREFIX)
        stash.call("[#{label}]#{url_part}")
      else
        translated_label = translate_protected_segment(label, target_locale: target_locale, source_locale: source_locale)
        stash.call("[#{translated_label}]#{url_part}")
      end
    end

    working.gsub!(/<\/?[a-zA-Z][^>\n]*>/) { |m| stash.call(m) }
    working.gsub!(/%\{[a-zA-Z0-9_]+\}/) { |m| stash.call(m) }
    working.gsub!(%r{https?://[^\s<>)\]]+}) { |m| stash.call(m) }
    [working, tokens]
  end

  def translate_protected_segment(segment, target_locale:, source_locale:)
    seg_tokens = []
    protected_seg = segment.gsub(/%\{[a-zA-Z0-9_]+\}|`[^`\n]+`/) do |m|
      idx = seg_tokens.length
      seg_tokens << m
      "#{TOKEN_PREFIX}#{idx}#{TOKEN_SUFFIX}"
    end
    out = translate_raw(protected_seg, target_locale: target_locale, source_locale: source_locale)
    out ? restore_tokens(out, seg_tokens) : segment
  end

  def restore_tokens(text, tokens)
    result = text.dup
    tokens.each_with_index.reverse_each do |original, idx|
      pattern = /_{0,2}\s*OODTOK\s*#{idx}(?!\d)\s*_{0,2}/i
      result.gsub!(pattern) { original }
    end
    result
  end

  def convert_osc_motd(content, target_locale:, source_locale:)
    parts = content.to_s.split(/^(\*+)\s*$/)
    parts.map do |chunk|
      if chunk.match?(/\A\*+\z/)
        chunk
      elsif chunk =~ /\A(\s*\d+[-\/.]\d+[-\/.]\d+\n---\s*)([^\n]*)\n([\s\S]*)\z/
        prefix = Regexp.last_match(1)
        title  = Regexp.last_match(2)
        body   = Regexp.last_match(3)
        t_title = convert_text(title, target_locale: target_locale, source_locale: source_locale)
        t_body  = convert_text(body, target_locale: target_locale, source_locale: source_locale)
        "#{prefix}#{t_title}\n#{t_body}"
      else
        chunk
      end
    end.join
  end

  def convert_rss_motd(content, target_locale:, source_locale:)
    content.to_s.gsub(/<(title|description)>([\s\S]*?)<\/\1>/i) do
      tag  = Regexp.last_match(1)
      body = Regexp.last_match(2)
      if body =~ /\A\s*<!\[CDATA\[([\s\S]*?)\]\]>\s*\z/
        inner = Regexp.last_match(1)
        t_inner = convert_text(inner, target_locale: target_locale, source_locale: source_locale)
        "<#{tag}><![CDATA[#{t_inner}]]></#{tag}>"
      else
        unescaped = CGI.unescapeHTML(body)
        t_inner = convert_text(unescaped, target_locale: target_locale, source_locale: source_locale)
        "<#{tag}>#{CGI.escapeHTML(t_inner)}</#{tag}>"
      end
    end
  end

  def same_unmodified_language?(src, dst)
    s = src.to_s.tr('_', '-').downcase
    d = dst.to_s.tr('_', '-').downcase
    return true if s == d
    return false if offline_styled_locale?(d)

    s.split('-').first == 'en' && d.split('-').first == 'en'
  end

  def apply_offline_style(text, target_locale)
    tag = target_locale.to_s.tr('_', '-').downcase
    rules = case tag
            when 'en-gb' then EN_GB_SPELLINGS
            when 'en-hg' then EN_HG_TERMS
            when 'en-cp' then EN_CP_TERMS
            else []
            end
    rules.reduce(text.dup) { |acc, (pat, rep)| acc.gsub(pat, rep) }
  end

  def api_lang_code(locale)
    bcp = MotdFile.bcp47_tag(locale)
    primary = bcp.split('-').first
    %w[zh pt].include?(primary) ? bcp : primary
  end

  def translate_raw(text, target_locale:, source_locale:)
    return apply_offline_style(text, target_locale) if offline_styled_locale?(target_locale)
    return @translator.call(text, target_locale.to_s, source_locale.to_s) if @translator

    if !@translate_url.empty?
      translate_via_endpoint(text, target_locale: target_locale, source_locale: source_locale)
    elsif !@google_api_key.empty?
      translate_via_google(text, target_locale: target_locale, source_locale: source_locale)
    end
  rescue StandardError => e
    Rails.logger.warn("OodLocaleConverter error (#{target_locale}): #{e.class}: #{e.message}") if defined?(Rails) && Rails.logger
    nil
  end

  def translate_via_google(text, target_locale:, source_locale:)
    out = translate_batch_via_google([text], target_locale: target_locale, source_locale: source_locale)
    out&.first
  end

  def translate_batch_via_google(texts, target_locale:, source_locale:)
    uri = URI('https://translation.googleapis.com/language/translate/v2')
    uri.query = URI.encode_www_form(key: @google_api_key)
    payload = {
      q:      texts,
      source: api_lang_code(source_locale),
      target: api_lang_code(target_locale),
      format: 'text'
    }
    res = post_json(uri, payload)
    items = res&.dig('data', 'translations')
    return nil unless items.is_a?(Array) && items.size == texts.size

    items.map { |entry| entry['translatedText'] ? CGI.unescapeHTML(entry['translatedText']) : nil }
  end

  def translate_via_endpoint(text, target_locale:, source_locale:)
    uri = URI(@translate_url)
    payload = {
      q:      text,
      source: api_lang_code(source_locale),
      target: api_lang_code(target_locale),
      format: 'text'
    }
    res = post_json(uri, payload)
    res&.dig('translatedText') || res&.dig('translation')
  end

  def post_json(uri, payload)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.open_timeout = 10
    http.read_timeout = 30
    req = Net::HTTP::Post.new(uri.request_uri, 'Content-Type' => 'application/json')
    req.body = JSON.generate(payload)
    resp = http.request(req)
    return nil unless resp.is_a?(Net::HTTPSuccess)

    JSON.parse(resp.body)
  end
end
