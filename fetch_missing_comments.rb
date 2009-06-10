require 'rubygems'
require 'mechanize'
require 'yaml'
require 'date'

$ua = WWW::Mechanize.new

$data = []

def extract_comments(link, comments)
  return unless link
  
  puts " Extract comments from #{link.href}"
  page = $ua.click(link)
  
  # Post Id
  post_id = page.root.css('div.entry').first[:id]
  
  page.root.css('div.comment').each do |comment|
    puts "  Process comment: #{comment[:id]}"

    # Extract the author and their details
    if comment.xpath('p[@class="comment-footer"]/a').size == 2
      # Author has a URL
      author_elem = comment.xpath('p[@class="comment-footer"]/a[1]').first
      author = author_elem.text.strip
      author_url = author_elem[:href]
    else
      author = ''
      author_url = ''
      if comment.xpath('p[@class="comment-footer"]').text =~ /Posted by:\s+([^\|]+)\|/m
        author = $1.strip
      end
    end
    
    # Date
    date_elem = comment.xpath('p[@class="comment-footer"]/a[last()]')
    # May 25, 2009 at 09:43 AM
    date = DateTime.strptime(date_elem.text, '%B %d, %Y at %I:%M %p')
    
    
    
    comments << {
      'body' => comment.css('div.comment-content span').first.inner_html,
      'author' => author,
      'authorEmail' => '',
      'authorUrl' => author_url,
      'dateCreated' => date.strftime('%m/%d/%Y %I:%M:%S %p'),
      'postid' => post_id
    }
    
  end

  page
end

def process_next_comment_page(page, comments)
  return unless page
  
  next_link = page.link_with(:text => /Next/, :href => %r{/comments/page/\d+/})
  next_page = extract_comments(next_link, comments)
  
  process_next_comment_page(next_page, comments)
end

def process_post(link)
  return unless link

  puts "Processing post #{link.href}"
  page = $ua.click(link)
  
  # Determine the post date/time
  date = page.root.css('h2.date-header').text
  time = ''
  if page.root.css('div.entry-footer span.post-footers').text =~ /Posted by .* at (\d{2}:\d{2} (AM|PM))/
    time = $1
  else
    puts " Unable to determine time of post"
    return
  end
  
  post_date = DateTime.strptime(date + ' ' + time, "%B %d, %Y %I:%M %p")
  
  post = {
    'permalink' => link.href.sub(/#comments$/, ''),
    'title' => page.root.css('h3.entry-header').text.strip,
    # dateCreated: '11/22/2006 04:02:34 PM'
    'dateCreated' => post_date.strftime('%m/%d/%Y %I:%M:%S %p'),
    'comments' => []
  }
  
  process_next_comment_page(page, post['comments'])
  $data << post
end

def process_page(url)
  return unless url
  
  puts "Processing #{url}"
  
  $ua.get(url) do |page|
    comment_links = page.links_with(:text => /Comments \(\d+\)/).select do |l|
      l.text =~ /Comments \((\d+)\)/ && $1.to_i > 50
    end
    comment_links.each do |link|
      process_post(link)
    end
    
    # Return the next page
    next_link = page.link_with(
      :text => /Next/,
      :href => %r{http://robinhanson.typepad.com/overcomingbias/page/\d+/}
    )
    return next_link ? next_link.href : nil
  end
end

url = 'http://robinhanson.typepad.com/overcomingbias/'
count = 0
while(url)
  url = process_page(url)
  # count += 1
  # break if count > 3
end

File.open('missing_comments.yml', 'w') do |f|
  YAML.dump($data, f)
end
