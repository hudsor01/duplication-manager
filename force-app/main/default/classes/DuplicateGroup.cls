/**
 * Represents a group of duplicate records with their match score
 *
 * @author Richard Hudson
 * @date April 2025
 */
public class DuplicateGroup {
    /**
     * List of records in this duplicate group
     */
    public List<SObject> records { get; private set; }

    /**
     * Match score for this group (0-100)
     */
    public Decimal matchScore { get; private set; }

    /**
     * Key used for identifying this group
     */
    public String groupKey { get; private set; }

    /**
     * Indicates if this is an exact match or fuzzy match
     */
    public Boolean isExactMatch { get; private set; }

    /**
     * Constructor for a duplicate group
     *
     * @param records List of records in the group
     * @param matchScore Match score for the group (0-100)
     * @param groupKey Key used for identifying this group
     * @param isExactMatch Indicates if this is an exact match
     */
    public DuplicateGroup(List<SObject> records, Decimal matchScore, String groupKey, Boolean isExactMatch) {
        this.records = records;
        this.matchScore = matchScore;
        this.groupKey = groupKey;
        this.isExactMatch = isExactMatch;
    }

    /**
     * Gets the master record based on the specified strategy
     *
     * @param strategy Strategy to use for selecting master record
     * @return The selected master record
     */
    public SObject getMasterRecord(String strategy) {
        if (this.records == null || this.records.isEmpty()) {
            return null;
        }

        if (this.records.size() == 1) {
            return this.records[0];
        }

        // Use strategy string to determine selection method
        SObject masterRecord;

        if (strategy == 'OldestCreated') {
            masterRecord = findOldestRecord();
        } else if (strategy == 'NewestCreated') {
            masterRecord = findNewestRecord();
        } else if (strategy == 'MostComplete') {
            masterRecord = findMostCompleteRecord();
        } else {
            // Default strategy
            masterRecord = findOldestRecord();
        }

        return masterRecord;
    }

    /**
     * Finds the oldest record by CreatedDate
     * @return The oldest record
     */
    private SObject findOldestRecord() {
        SObject oldest = this.records[0];
        Datetime oldestDate = (Datetime)oldest.get('CreatedDate');

        for (SObject record : this.records) {
            Datetime createdDate = (Datetime)record.get('CreatedDate');
            if (createdDate != null && (oldestDate == null || createdDate < oldestDate)) {
                oldest = record;
                oldestDate = createdDate;
            }
        }

        return oldest;
    }

    /**
     * Finds the newest record by CreatedDate
     * @return The newest record
     */
    private SObject findNewestRecord() {
        SObject newest = this.records[0];
        Datetime newestDate = (Datetime)newest.get('CreatedDate');

        for (SObject record : this.records) {
            Datetime createdDate = (Datetime)record.get('CreatedDate');
            if (createdDate != null && (newestDate == null || createdDate > newestDate)) {
                newest = record;
                newestDate = createdDate;
            }
        }

        return newest;
    }

    /**
     * Finds the most complete record (with most non-null fields)
     * @return The most complete record
     */
    private SObject findMostCompleteRecord() {
        SObject mostComplete = this.records[0];
        Integer maxNonNullCount = countNonNullFields(mostComplete);

        for (SObject record : this.records) {
            Integer nonNullCount = countNonNullFields(record);
            if (nonNullCount > maxNonNullCount) {
                mostComplete = record;
                maxNonNullCount = nonNullCount;
            }
        }

        return mostComplete;
    }

    /**
     * Counts the number of non-null field values in a record
     * @param record The record to check
     * @return Number of non-null fields
     */
    private Integer countNonNullFields(SObject record) {
        Integer count = 0;
        Map<String, Object> fieldsToValues = record.getPopulatedFieldsAsMap();

        for (Object value : fieldsToValues.values()) {
            if (value != null) {
                count++;
            }
        }

        return count;
    }

    /**
     * Gets the duplicate records (all records except the master)
     *
     * @param masterRecord The master record
     * @return List of duplicate records
     */
    public List<Id> getDuplicateIds(SObject masterRecord) {
        if (masterRecord == null || this.records == null || this.records.isEmpty()) {
            return new List<Id>();
        }

        List<Id> duplicateIds = new List<Id>();
        for (SObject record : this.records) {
            if (record.Id != masterRecord.Id) {
                duplicateIds.add(record.Id);
            }
        }

        return duplicateIds;
    }

    /**
     * Gets the number of records in this group
     *
     * @return Number of records
     */
    public Integer getRecordCount() {
        return (this.records != null) ? this.records.size() : 0;
    }

    /**
     * Checks if this group contains duplicate records
     *
     * @return True if the group has multiple records
     */
    public Boolean hasDuplicates() {
        return getRecordCount() > 1;
    }
}
