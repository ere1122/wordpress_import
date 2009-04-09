UPDATE posts SET post_content = REPLACE(post_content,'\n', '') where post_content like "%<p%";
