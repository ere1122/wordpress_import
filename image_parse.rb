require 'uri'
require 'pathname'
require 'cgi'

def process_images
  logger = Logger.new('error_image_parse.log')
  WpPost.find(:all).each do |post|
    html_doc = Nokogiri::HTML(post.post_content)
    (html_doc/"img").each do |img|
      img_src = URI.parse(img.attributes['src'].to_s.gsub(' ', '%20'))
      
      unless img_src.host =~ /(overcomingbias|robinhanson)/
        msg = "NOT Downloading image: #{img_src}"
        logger.info msg 
        puts msg
        next
      end

      img_name = Pathname(img_src.path).basename.to_s
      img_str = ''

      msg = "Downloading image: #{img_src}"
      logger.info msg
      puts msg
      begin
        open(img_src) do |f|
          img_str = f.read
        end
        img_root = "/#{post.post_date.year}/#{"%02d" % post.post_date.month}"
        dest_save_dir = "#{$wordpress_root}#{$site_root}/#{img_root}"
        FileUtils.mkdir_p dest_save_dir
        dest_save_image = "#{dest_save_dir}/#{img_name}"
        dest_site_image = "#{$site_root}#{img_root}/#{img_name}"
        File.open(dest_save_image, 'w') {|f| f.write(img_str) }
        img.attributes['src'].value = dest_site_image
        if img.parent.node_name == 'a'
          img.parent.attributes['href'].value = dest_site_image
        end
        post.post_content = html_doc.inner_html
        post.save
      rescue
        msg = "Could not download image for : #{img_src}: #{$!}"
        puts msg
        logger.error msg
      end
    end
  end

end
