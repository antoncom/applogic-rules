local db_utils = require "applogic.modifier.db_utils"
local json = require "cjson"

-- Database path
local db_path = "/etc/leveldb/journal.db"

-- Test: Insert a sample journal entry
local sample_journal = {
    datetime = "2024-09-23 10:30:00",
    name = "Test Signal",
    command = "AT+CSQ",
    source = "Modem Test",
    response = "OK"
}

local ruleid = "test_rule_1"

print("Inserting sample journal entry...")
db_utils.insert_journal(db_path, ruleid, json.encode(sample_journal))

-- Test: List all journal entries
print("\nListing all journal entries...")
local entries = db_utils.list_journal_entries(db_path)
for _, entry in ipairs(entries) do
    print("Key: " .. entry.key)
    print("Journal Data: " .. json.encode(entry.data.journal))
end

-- Test: Retrieve a specific entry (use the first entry's key for retrieval)
if #entries > 0 then
    local test_key = entries[1].key
    print("\nRetrieving entry with key: " .. test_key)
    local retrieved_entry = db_utils.get(db_path, test_key)

    if retrieved_entry then
        local decoded_entry = json.decode(retrieved_entry)
        print("Decoding Journal Data: " .. retrieved_entry)

        -- Decode the nested JSON in the 'journal' field
        if decoded_entry and decoded_entry.journal then
            local decoded_journal = json.decode(decoded_entry.journal)
            if decoded_journal then
                print("Retrieved Journal Entry:")
                print("Date/Time: ", decoded_journal.datetime)
                print("Name: ", decoded_journal.name)
                print("Command: ", decoded_journal.command)
                print("Source: ", decoded_journal.source)
                print("Response: ", decoded_journal.response)
            else
                print("Failed to decode the journal field.")
            end
        else
            print("Journal entry not found or improperly formatted.")
        end
    else
        print("Entry not found!")
    end
else
    print("No entries found in the database.")
end
