require 'rubygems'
require 'yaml'
require 'uri'
require 'pathname'
require 'date'
require 'nokogiri'
require 'activerecord'
require 'logger'
require 'optparse'

$logger = Logger.new(STDOUT)
$logger.level = Logger::INFO

$options = {:apply => false}
OptionParser.new do |opts|
  opts.banner =   "Usage: import_missing_comments.rb [--apply|-a] wp-config.php missing_comments.yml"
  
  opts.on('-a', '--apply', "Apply chnages to the database") do |a|
    $options[:apply] = a
  end
  
  opts.on_tail("-h", "--help", "Show this message") do
    puts opts
    exit
  end
end.parse!

if ARGV.size < 2
  puts "Usage: import_missing_comments.rb [--apply|-a] wp-config.php missing_comments.yml"
  exit 2
end

class WpPost < ActiveRecord::Base
  set_primary_key 'ID'
  set_table_name "posts"
  has_many :comments, :class_name => 'WpComment', :foreign_key => 'comment_post_ID'
end
class WpComment < ActiveRecord::Base
  set_primary_key 'comment_ID'
  set_table_name "comments" 
end

def comment_excerpt(comment)
  excerpt = comment['body'][0,50].gsub("\n", '')
  "comment by '#{comment['author']}': #{excerpt}"
end

def comment_exists?(post, comment)
  # Check if this comment already exists using brutal compare on content
  # Nokogiri is used to parse as HTML in order to remove markup
  key = Nokogiri::HTML(comment['body']).content.gsub(/[^a-zA-Z0-9]*/, '') + comment['author']
  post.comments.each do |wp_comment|
    wp_key = Nokogiri::HTML(wp_comment.comment_content).content.gsub(/[^a-zA-Z0-9]*/, '') + wp_comment.comment_author
    if key == wp_key
      $logger.warn " Skipping existing #{comment_excerpt(comment)}"
      return true
    end
  end
  
  false
end

$import_count = 0;
def process_comments_on_post(post, comments)
  comments.each do |comment|
    next if comment_exists?(post, comment)

    # Parse the date assuming (US) EST 
    comment_date= DateTime.strptime(comment['dateCreated'] + ' -5000', '%m/%d/%Y %I:%M:%S %p %z')
    
    if $options[:apply]
      # Import the new comment
      post.comments.create! do |c|
        c.comment_author  = comment['author']
        c.comment_author_email = comment['authorEmail']
        c.comment_author_url = comment['authorUrl']
        c.comment_author_IP = '127.0.0.1'
        c.comment_date = comment_date
        c.comment_date_gmt = comment_date.new_offset(0)
        c.comment_content = comment['body']
        c.comment_karma = 0
        c.comment_approved = 1
        c.comment_agent = 'Missing Comment Importer'
        c.comment_type = ''
        c.comment_parent = 0
        c.user_id = 0
      end
    end
    $import_count += 1
    $logger.info " Imported #{comment_excerpt(comment)}"
  end
end

# Get the DB config
wp_config = File.open(ARGV[0]).readlines.grep(/define\(/)
config = {}
wp_config.each do |line|
  if line =~ /define\(\s*'([^']+)',\s+'([^']+)'\s*\);/
    config[$1.downcase.to_sym] = $2
  end
end

# p config
$logger.info "--apply option not provided, not applying changes to database" unless $options[:apply]

$logger.debug "Loading missing comments"
missing_comments = []
File.open(ARGV[1]) do |comments_file|
  missing_comments = YAML.load(comments_file)
end
$logger.debug "Done"

ActiveRecord::Base.logger = $logger

ActiveRecord::Base.establish_connection(
  :adapter  => "mysql",
  :database => config[:db_name],
  :username => config[:db_user],
  :password => config[:db_password],
  # :socket => ''
  :host => config[:db_host]
)

missing_comments.each do |post|
  old_permalink = URI.parse(post['permalink'])
  
  $logger.info "Importing comments on: #{post['permalink']}"
  
  post_name = Pathname(old_permalink.path).basename('.html').to_s
  post_name.sub!(/-+$/, '')
  
  
  posts = []
  if post['title'] == 'Open Thread'
    # Special case for open-thread, match on date and title
    date = DateTime.strptime(post['dateCreated'], '%m/%d/%Y %I:%M:%S %p')
    posts = WpPost.find(:all, :conditions => ['post_title = ? AND post_date LIKE ?', post['title'], date])
  elsif post_name == 'expelled-beats'
    posts = WpPost.find_all_by_post_name('expelled-beats-sicko')
  elsif post_name == 'terrible-optimi'
    posts = WpPost.find_all_by_post_name('nature-endorses-human-extinction')
  else
    posts = WpPost.find_all_by_post_name_and_post_title(post_name, post['title'])
  end

  if posts.size > 1
    $logger.error "Got multiple results for '#{post_name}', '#{post['title']}'"
    raise Exception
  elsif posts.empty?
    $logger.error "Got no results for '#{post_name}', '#{post['title']}'"
    raise Exception
  end
  
  wp_post = posts.first
  process_comments_on_post(wp_post, post['comments'])
end

puts "#{$import_count} comments imported"
