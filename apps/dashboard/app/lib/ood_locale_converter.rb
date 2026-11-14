# frozen_string_literal: true

require 'cgi'
require 'json'
require 'net/http'
require 'uri'

# Admin CLI helper for converting Open OnDemand app YAML strings and MOTD files
# into static on-disk locale files (`<app>/locales/<locale>.yml` and `motd.<locale>`).
#
# Never invoked during live user PUN web requests: translations are materialized
# once as static files on disk via `rake ood:locales:sync_apps` / `ood:locales:sync_motd`.
class OodLocaleConverter
  TOKEN_PREFIX = '__OODTOK'
  TOKEN_SUFFIX = '__'

  def initialize(
    google_api_key: ENV['GOOGLE_TRANSLATE_API_KEY'],
    translate_url:  ENV['OOD_TRANSLATE_URL'],
    translator:     nil
  )
    @google_api_key = google_api_key.to_s.strip
    @translate_url  = translate_url.to_s.strip
    @translator     = translator
  end

  def available?
    !@translator.nil? || !@google_api_key.empty? || !@translate_url.empty?
  end

  # Convert a Markdown, ERB, HTML, or plain string while preserving fenced/inline
  # code, ERB `<% ... %>` tags, HTML tags, `%{var}` interpolations, and link URLs.
  def convert_text(text, target_locale:, source_locale: 'en')
    return text if text.nil? || !available?

    str = text.to_s
    return str if str.strip.empty?
    return str if same_primary_language?(source_locale, target_locale)

    tokens = []
    stash = lambda do |raw|
      idx = tokens.length
      tokens << raw
      "#{TOKEN_PREFIX}#{idx}#{TOKEN_SUFFIX}"
    end

    working = str.dup
    # 1. Fenced code blocks (```...``` or ~~~...~~~)
    working.gsub!(/(?:```[\s\S]*?```|~~~[\s\S]*?~~~)/) { |m| stash.call(m) }
    # 2. ERB tags (<% ... %>) for markdown_erb / text_erb safety
    working.gsub!(/<%[\s\S]*?%>/) { |m| stash.call(m) }
    # 3. Inline code spans (`...`)
    working.gsub!(/`[^`\n]+`/) { |m| stash.call(m) }
    # 4. Markdown links `[label](url)`: translate prose `label`, protect `(url)`
    working.gsub!(/\[([^\[\]\n]+)\](\([^\)\s]+(?:\s+"[^"]*")?\))/) do
      label = Regexp.last_match(1)
      url_part = Regexp.last_match(2)
      if label.match?(%r{\Ahttps?://}i) || label.include?(TOKEN_PREFIX)
        stash.call("[#{label}]#{url_part}")
      else
        translated_label = translate_protected_segment(label, target_locale: target_locale, source_locale: source_locale)
        stash.call("[#{translated_label}]#{url_part}")
      end
    end
    # 5. HTML tags (<tag ...>)
    working.gsub!(/<\/?[a-zA-Z][^>\n]*>/) { |m| stash.call(m) }
    # 6. Rails I18n placeholders (%{var}) and raw URLs
    working.gsub!(/%\{[a-zA-Z0-9_]+\}/) { |m| stash.call(m) }
    working.gsub!(%r{https?://[^\s<>)\]]+}) { |m| stash.call(m) }

    translated = translate_raw(working, target_locale: target_locale, source_locale: source_locale)
    return str if translated.nil?

    restore_tokens(translated, tokens)
  end

  # Convert MOTD content while preserving all 6 Open OnDemand MOTD formats:
  # `plaintext`, `markdown`, `markdown_erb`, `text_erb`, `osc`, and `rss`.
  def convert_motd(content, target_locale:, source_locale: 'en', format: ENV['MOTD_FORMAT'])
    return content if content.nil? || !available?

    case format.to_s.strip.downcase
    when 'osc'
      convert_osc_motd(content, target_locale: target_locale, source_locale: source_locale)
    when 'rss'
      convert_rss_motd(content, target_locale: target_locale, source_locale: source_locale)
    else
      # Covers plaintext, markdown, markdown_erb, and text_erb (ERB tags & Markdown protected)
      convert_text(content, target_locale: target_locale, source_locale: source_locale)
    end
  end

  private

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
    # Allow minor whitespace/case adjustments around token markers from MT engines
    tokens.each_with_index do |original, idx|
      pattern = /__\s*OODTOK\s*#{idx}\s*__/i
      result.gsub!(pattern) { original }
    end
    result
  end

  def convert_osc_motd(content, target_locale:, source_locale:)
    # Preserve `******` section dividers and `YYYY/MM/DD\n--- Title\nBody` structure
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
    # Translate only <title> and <description> inner text/CDATA; keep XML tags, <link>, <pubDate>, <guid> untouched
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

  def same_primary_language?(src, dst)
    s = src.to_s.tr('_', '-').downcase
    d = dst.to_s.tr('_', '-').downcase
    s == d || (s.split('-').first == 'en' && d.split('-').first == 'en')
  end

  def api_lang_code(locale)
    bcp = MotdFile.bcp47_tag(locale)
    primary = bcp.split('-').first
    %w[zh pt].include?(primary) ? bcp : primary
  end

  def translate_raw(text, target_locale:, source_locale:)
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
    uri = URI('https://translation.googleapis.com/language/translate/v2')
    uri.query = URI.encode_www_form(key: @google_api_key)
    payload = {
      q:      text,
      source: api_lang_code(source_locale),
      target: api_lang_code(target_locale),
      format: 'text'
    }
    res = post_json(uri, payload)
    res&.dig('data', 'translations', 0, 'translatedText')
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
    http.read_timeout = 20
    req = Net::HTTP::Post.new(uri.request_uri, 'Content-Type' => 'application/json')
    req.body = JSON.generate(payload)
    resp = http.request(req)
    return nil unless resp.is_a?(Net::HTTPSuccess)

    JSON.parse(resp.body)
  end
end
