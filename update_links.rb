require 'url_mapping.rb'

def update_permalinks

  logger = Logger.new('url_update_error.log')

  url_mapping_arr.each do |url_mapping|
    new_post_url = url_mapping[0].strip
    old_post_url = url_mapping[1].strip
    if new_post_url == '' or old_post_url == '' or new_post_url.nil? or old_post_url.nil?
      msg = "ERROR UPDATING NEW-#{new_post_url}------OLD-#{old_post_url}"
      puts msg
      logger.error msg
      next
    elsif new_post_url != old_post_url
      wp_post = WpPost.find_by_post_name(new_post_url)
      unless wp_post.nil?
        wp_post.update_attribute(:post_name, old_post_url)
        msg = "Updated #{new_post_url} -> #{old_post_url}"
        puts msg
        logger.info msg
      else
        msg = "ERROR COULD NOT FIND NEW URL - #{new_post_url}"
        puts msg
        logger.error msg
      end
    else
      msg = "Skipping #{new_post_url}, no change"
      puts msg
      logger.info msg
    end
  end

end
