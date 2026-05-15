#!/usr/bin/env ruby
# find_crystal_shards.rb
# Search and evaluate Crystal shards

require 'net/http'
require 'json'
require 'uri'
require 'open-uri'
require 'nokogiri'
require 'date'
require 'yaml'

class CrystalShardFinder
  def initialize(query)
    @query = query
    @results = []
  end

  def search_shards_info
    url = "https://shards.info/search?query=#{URI.encode_www_form_component(@query)}"
    response = fetch_with_redirects(url)
    if response.is_a?(Net::HTTPSuccess)
      parse_shards_info_response(response.body)
    else
      puts "Failed to search shards.info: #{response.code} #{response.message}"
    end
  end

  def fetch_with_redirects(url, limit = 5)
    raise 'Too many redirects' if limit <= 0

    uri = URI(url)
    response = Net::HTTP.get_response(uri)

    case response
    when Net::HTTPRedirection
      location = response['location']
      next_url = URI.join(url, location).to_s
      fetch_with_redirects(next_url, limit - 1)
    else
      response
    end
  end

  def parse_shards_info_response(html)
    doc = Nokogiri::HTML(html)
    seen = {}

    # shards.info search currently renders relative links like /github/owner/repo/
    doc.css('a[href^="/github/"]').each do |link|
      href = link['href'].to_s
      match = href.match(%r{\A/github/([^/]+)/([^/]+)/?\z})
      next unless match

      owner = match[1]
      repo = match[2]
      key = "#{owner}/#{repo}"
      next if seen[key]
      seen[key] = true

      name = repo
      description = extract_description(link)
      github_url = "https://github.com/#{owner}/#{repo}"
      @results << {
        name: name,
        description: description,
        stars: 0,
        github_url: github_url
      }
    end
  end

  def extract_description(link_node)
    card = link_node.ancestors('div').find { |d| d['class'].to_s.include?('card') }
    return '' unless card

    candidate = card.css('p').map { |p| p.text.strip }.find { |t| !t.empty? }
    candidate || ''
  end

  def evaluate_shard(github_url)
    return {} unless github_url

    # Extract owner/repo from GitHub URL
    match = github_url.match(%r{github\.com/([^/]+)/([^/]+)})
    return {} unless match

    owner = match[1]
    repo = match[2]

    # Get GitHub repo info via GitHub API (requires token for higher rate limits)
    repo_info = get_github_repo_info(owner, repo)

    # Check crystaldoc.info
    crystaldoc_url = "https://www.crystaldoc.info/github.com/#{owner}/#{repo}"
    has_docs = check_crystaldoc(crystaldoc_url)

    {
      owner: owner,
      repo: repo,
      stars: repo_info[:stars] || 0,
      forks: repo_info[:forks] || 0,
      last_commit: repo_info[:last_commit],
      open_issues: repo_info[:open_issues] || 0,
      has_docs: has_docs,
      crystaldoc_url: crystaldoc_url,
      quality_score: calculate_quality_score(repo_info, has_docs)
    }
  end

  def get_github_repo_info(owner, repo)
    # NOTE: GitHub API requires authentication for higher rate limits
    # For public access with limited rate, use unauthenticated requests
    url = "https://api.github.com/repos/#{owner}/#{repo}"
    uri = URI(url)

    request = Net::HTTP::Get.new(uri)
    # Add token if available: request['Authorization'] = "token #{ENV['GITHUB_TOKEN']}"

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end

    if response.is_a?(Net::HTTPSuccess)
      data = JSON.parse(response.body)
      {
        stars: data['stargazers_count'],
        forks: data['forks_count'],
        last_commit: data['pushed_at'],
        open_issues: data['open_issues_count'],
        archived: data['archived']
      }
    else
      puts "GitHub API error: #{response.code} #{response.message}"
      {}
    end
  rescue StandardError => e
    puts "Error fetching GitHub info: #{e.message}"
    {}
  end

  def check_crystaldoc(url)
    uri = URI(url)
    response = Net::HTTP.get_response(uri)
    response.is_a?(Net::HTTPSuccess)
  rescue StandardError
    false
  end

  def calculate_quality_score(repo_info, has_docs)
    score = 0

    # Stars: 0-10 points (50+ stars = 10 points)
    score += [repo_info[:stars].to_i / 5, 10].min

    # Recent activity: 0-10 points (within 6 months = 10 points)
    if repo_info[:last_commit]
      last_commit_date = Date.parse(repo_info[:last_commit])
      months_ago = (Date.today - last_commit_date).to_i / 30
      score += [10 - months_ago, 0].max
    end

    # Documentation: 0-5 points
    score += 5 if has_docs

    # Not archived: 5 points
    score += 5 unless repo_info[:archived]

    # Issues ratio: 0-5 points (fewer open issues better)
    open_issues = repo_info[:open_issues].to_i
    score += [5 - (open_issues / 10), 0].max

    score
  end

  def run
    puts "Searching for Crystal shards: #{@query}"
    search_shards_info

    puts "\nFound #{@results.size} shards:"
    @results.each_with_index do |shard, i|
      puts "\n#{i + 1}. #{shard[:name]}"
      puts "   Description: #{shard[:description]}"
      puts "   Stars: #{shard[:stars]}"

      next unless shard[:github_url]

      evaluation = evaluate_shard(shard[:github_url])
      puts "   GitHub: #{shard[:github_url]}"
      puts "   Quality Score: #{evaluation[:quality_score]}/35"
      puts "   Has CrystalDoc: #{evaluation[:has_docs] ? 'Yes' : 'No'}"
      puts "   Last Commit: #{evaluation[:last_commit]}"
      puts "   Open Issues: #{evaluation[:open_issues]}"
      puts "   Archived: #{evaluation[:archived] ? 'Yes' : 'No'}"

      # Recommendation
      if evaluation[:quality_score] >= 20
        puts '   ✅ RECOMMENDED'
      elsif evaluation[:quality_score] >= 10
        puts '   ⚠️  CONSIDER WITH CAUTION'
      else
        puts '   ❌ NOT RECOMMENDED'
      end
    end
  end
end

def install_shard(dependency_name, github_repo, shard_file = 'shard.yml')
  unless github_repo.match?(%r{\A[^/]+/[^/]+\z})
    warn "Invalid github repo '#{github_repo}'. Expected format: owner/repo"
    exit 1
  end

  shard_data = File.exist?(shard_file) ? (YAML.load_file(shard_file) || {}) : {}
  shard_data['dependencies'] ||= {}

  if shard_data['dependencies'].key?(dependency_name)
    puts "Dependency '#{dependency_name}' already exists in #{shard_file}."
    return
  end

  shard_data['dependencies'][dependency_name] = { 'github' => github_repo }
  File.write(shard_file, YAML.dump(shard_data))

  puts "Added '#{dependency_name}' => '#{github_repo}' to #{shard_file}."
  puts 'Next: shards install'
end

if ARGV[0] == '--install'
  if ARGV.size != 3
    warn 'Usage: ruby find_crystal_shards.rb --install <dependency_name> <owner/repo>'
    exit 1
  end
  install_shard(ARGV[1], ARGV[2])
  exit 0
end

if ARGV.empty?
  puts 'Usage: ruby find_crystal_shards.rb <search-query> OR --install <dependency_name> <owner/repo>'
  exit 1
end

finder = CrystalShardFinder.new(ARGV.join(' '))
finder.run
