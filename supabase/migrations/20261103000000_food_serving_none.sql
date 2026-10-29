-- USDA Branded rows used the text "None" as a household serving, so servings read "None (28 g)".
-- scripts/gen_foods.py now drops it; this cleans rows already loaded.
update foods set serving = regexp_replace(serving, '^None \(([^)]*)\)$', '\1') where serving ~ '^None \([^)]*\)$';
update foods set serving = '1 serving' where serving = 'None';
