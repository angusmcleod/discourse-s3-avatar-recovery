# frozen_string_literal: true

# name: discourse-s3-avatar-recovery
# about: Recover tombstoned avatars from s3
# version: 0.1
# authors: Angus McLeod (angusmcleod)
# url: https://github.com/paviliondev/discourse-s3-avatar-recovery

after_initialize do
  add_to_class(:upload_recovery, :recover_avatars) do
    will_recover = []
    
    User.find_each do |user|
      begin
        if user.has_uploaded_avatar
          upload = user.uploaded_avatar
          
          unless upload.local?
            
            ## we are only extracting a subset of the logic in recover_from_s3
            ## here as we don't want to do everything that method does,
            ## e.g. re-add the upload record
            
            sha1 = upload.sha1
            
            @object_keys ||= begin
              s3_helper = Discourse.store.s3_helper

              if Rails.configuration.multisite
                current_db = RailsMultisite::ConnectionManagement.current_db
                s3_helper.list("uploads/#{current_db}/original").map(&:key).concat(
                  s3_helper.list("uploads/#{FileStore::S3Store::TOMBSTONE_PREFIX}#{current_db}/original").map(&:key)
                )
              else
                s3_helper.list("original").map(&:key).concat(
                  s3_helper.list("#{FileStore::S3Store::TOMBSTONE_PREFIX}original").map(&:key)
                )
              end
            end
            
            @object_keys.each do |key|
              if key =~ /#{sha1}/
                tombstone_prefix = FileStore::S3Store::TOMBSTONE_PREFIX

                if key.include?(tombstone_prefix)
                  if @dry_run
                    will_recover.push("#{user.username} #{key}")
                  else
                    old_key = key
                    key = key.sub(tombstone_prefix, "")
                    
                    Discourse.store.s3_helper.copy(
                      old_key,
                      key,
                      options: { acl: "public-read" }
                    )
                  end
                end
              end
            end
          end
        end
      rescue => e
        raise e if @stop_on_error
        puts "Error: #{user.username} #{e.class}: #{e.message}"
      end
    end
    
    if will_recover.any?
      puts "Will attempt to recover these avatars:"
      puts will_recover.join("\n")
    end
  end
end