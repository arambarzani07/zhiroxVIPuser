-- Kurdish-first labels for platform feature catalog.
-- Internal feature keys stay stable; only user-facing labels/descriptions change.

update public.platform_feature_catalog
set display_name = case feature_key
      when 'customer_notifications' then 'ئاگادارکردنەوەی کڕیار'
      when 'automated_backup' then 'پاشەکەوتی خۆکار'
      when 'data_export' then 'بردنەدەرەوەی داتا'
      when 'data_import' then 'هێنانەژوورەوەی داتا'
      when 'advanced_reports' then 'ڕاپۆرتی پێشکەوتوو'
      when 'external_integrations' then 'پەیوەستکردنی دەرەکی'
      else display_name
    end,
    description = case feature_key
      when 'customer_notifications' then 'ئاگادارکردنەوەی وێب و ناردنی خۆکار یان دەستی'
      when 'automated_backup' then 'پاشەکەوت و چاودێری دۆخی پلاتفۆرم'
      when 'data_export' then 'بردنەدەرەوەی داتای خۆی مارکێت'
      when 'data_import' then 'هێنانەژوورەوەی داتای خۆی مارکێت'
      when 'advanced_reports' then 'ڕاپۆرت و شیکردنەوەی پێشکەوتوو'
      when 'external_integrations' then 'پەیوەستکردن بە خزمەتگوزارییە دەرەکییە ڕێگەپێدراوەکان'
      else description
    end,
    updated_at = now()
where feature_key in (
  'customer_notifications',
  'automated_backup',
  'data_export',
  'data_import',
  'advanced_reports',
  'external_integrations'
);
