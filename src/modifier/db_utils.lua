local leveldb = require 'lualeveldb'
local json = require 'cjson' 

local db_utils = {}

-- Set max elements
local max_elements = 20

-- Database options
function db_utils.get_db_options()
    local opt = leveldb.options()
    opt.createIfMissing = true
    opt.errorIfExists = false
    return opt
end

-- Open the database
function db_utils.open_db(db_file)
    local opt = db_utils.get_db_options()
    return leveldb.open(opt, db_file)
end

-- Close the database
function db_utils.close_db(db)
    leveldb.close(db)
end

-- Insert a new journal entry (opens and closes the database in the function)
function db_utils.insert_journal(db_file, ruleid, journal)
    -- Check current number of entries
    local entries = db_utils.list_journal_entries(db_file)

    print("Total records in the DB: " .. tostring(entries))
    
    -- If we exceed max elements, delete the oldest
    if #entries >= max_elements then
        db_utils.delete_oldest_entry(db_file, entries)
    end

    entries = db_utils.list_journal_entries(db_file)

    print("After deleting, the total records in the DB: " .. tostring(entries))
    
    -- Insert the new entry
    local data = {
        journal = journal,
        ruleid = ruleid
    }
    local key = os.time() .. "_" .. ruleid -- unique key using timestamp and ruleid
    -- Open the database
    local db = db_utils.open_db(db_file)

    assert(db:put(key, json.encode(data)))
    -- Close the database after the operation
    db_utils.close_db(db)
end

-- List all journal entries (opens and closes the database in the function)
function db_utils.list_journal_entries(db_file)
    local db = db_utils.open_db(db_file)
    local iter = db:iterator()
    iter:seekToFirst()
    local entries = {}
    
    while iter:valid() do
        local key = iter:key()
        local value = iter:value()
        local decoded = json.decode(value)
        
        -- Insert the decoded entry into the table
        table.insert(entries, {key = key, data = decoded})
        iter:next()
    end
    
    iter:del() -- Clean up iterator

    -- Sort entries by `datetime` field (need to decode the 'journal' field first)
    table.sort(entries, function(a, b)
        -- Decode the nested 'journal' field for both entries
        local a_journal = json.decode(a.data.journal)
        local b_journal = json.decode(b.data.journal)
        
        -- Safeguard in case the 'journal' field is missing or malformed
        if a_journal and b_journal then
            return a_journal.datetime < b_journal.datetime
        else
            return false
        end
    end)

    -- Close the database after listing
    db_utils.close_db(db)
    
    return entries
end


-- Delete the oldest entry by datetime (opens and closes the database in the function)
function db_utils.delete_oldest_entry(db_file, entries)

    local entries = db_utils.list_journal_entries(db_file)

    local db = db_utils.open_db(db_file)
    -- Assuming entries are sorted by datetime
    local oldest_entry = entries[1]
    if oldest_entry then
        local key = oldest_entry.key
        db:delete(key)
    end

    -- Close the database after deleting
    db_utils.close_db(db)
end

-- Get a value by key (opens and closes the database in the function)
function db_utils.get(db_file, key)
    local db = db_utils.open_db(db_file)
    local value = db:get(key)
    db_utils.close_db(db)
    return value
end

return db_utils
