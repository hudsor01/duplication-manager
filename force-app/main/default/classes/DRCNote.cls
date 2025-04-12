/**
 * Class for creating note records
 * @author Richard Hudson
 * @date 2025-04-11
 */
public class DRCNote {
    /**
     * Static method for creating a note record
     *
     * @param parentId ID of the parent record
     * @param title Title of the note
     * @param body Body content of the note
     * @return Boolean indicating success
     */
    @AuraEnabled
    public static Boolean createNote(Id parentId, String title, String body) {
        if (parentId == null) {
            throw new AuraHandledException('Parent record ID is required');
        }
        
        if (String.isBlank(title)) {
            title = 'Data from merged records';
        }
        
        try {
            // Create a standard Note instead of ContentNote (which might not be available)
            Note noteRecord = new Note();
            noteRecord.Title = title;
            noteRecord.Body = body;
            noteRecord.ParentId = parentId;
            
            insert noteRecord;
            
            return true;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating note: ' + e.getMessage());
        }
    }
}