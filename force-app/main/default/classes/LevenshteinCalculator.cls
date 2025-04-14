/**
 * Utility class for calculating Levenshtein distance between strings
 * 
 * @author Richard Hudson
 * @date April 2025
 */
public class LevenshteinCalculator {
    // Cache of previously calculated distances
    private static Map<String, Integer> distanceCache = new Map<String, Integer>();
    
    /**
     * Calculates Levenshtein distance between two strings
     * 
     * @param s1 First string
     * @param s2 Second string
     * @return Levenshtein distance
     */
    public static Integer distance(String s1, String s2) {
        // Handle null values
        if (s1 == null) s1 = '';
        if (s2 == null) s2 = '';
        
        // Check for simple cases
        if (s1 == s2) return 0;
        if (s1.length() == 0) return s2.length();
        if (s2.length() == 0) return s1.length();
        
        // Check cache first
        String cacheKey = s1 + '|' + s2;
        if (distanceCache.containsKey(cacheKey)) {
            return distanceCache.get(cacheKey);
        }
        
        // Create distance matrix as a List of Lists
        List<List<Integer>> distanceMatrix = new List<List<Integer>>();
        
        // Initialize the matrix with zeros
        for (Integer i = 0; i <= s1.length(); i++) {
            distanceMatrix.add(new List<Integer>());
            for (Integer j = 0; j <= s2.length(); j++) {
                distanceMatrix[i].add(0);
            }
        }
        
        // Initialize first row and column
        for (Integer i = 0; i <= s1.length(); i++) {
            distanceMatrix[i][0] = i;
        }
        
        for (Integer j = 0; j <= s2.length(); j++) {
            distanceMatrix[0][j] = j;
        }
        
        // Fill in the rest of the matrix
        for (Integer i = 1; i <= s1.length(); i++) {
            for (Integer j = 1; j <= s2.length(); j++) {
                Integer cost = (s1.substring(i-1, i) == s2.substring(j-1, j)) ? 0 : 1;
                
                distanceMatrix[i][j] = Math.min(
                    Math.min(
                        distanceMatrix[i-1][j] + 1,     // deletion
                        distanceMatrix[i][j-1] + 1      // insertion
                    ),
                    distanceMatrix[i-1][j-1] + cost     // substitution
                );
            }
        }
        
        // Get the final distance
        Integer result = distanceMatrix[s1.length()][s2.length()];
        
        // Cache the result if strings aren't too long
        if (s1.length() + s2.length() < 200) {
            distanceCache.put(cacheKey, result);
        }
        
        return result;
    }
    
    /**
     * Clears the distance cache
     */
    public static void clearCache() {
        distanceCache.clear();
    }
    
    /**
     * Alternative name for distance method for backwards compatibility
     * 
     * @param s1 First string
     * @param s2 Second string
     * @return Levenshtein distance
     */
    public static Integer calculateDistance(String s1, String s2) {
        return distance(s1, s2);
    }
}