public class TextMatcher implements FieldMatcherInterface {
    public Boolean canHandleField(String fieldName) {
        // Minimal check for fields containing 'text'
        return fieldName != null && fieldName.toLowerCase().contains('text');
    }
    
    public Decimal calculateMatchScore(String value1, String value2) {
        // Basic implementation: 100 for exact match, else 0
        if (value1 == value2) {
            return 100;
        }
        return 0;
    }
}