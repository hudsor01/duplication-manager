/**
 * Specialized matcher for email fields with advanced matching capabilities
 * Enhanced with Gmail-specific normalization, domain-aware matching, and typo detection
 *
 * @author Richard Hudson
 * @date April 2025
 * @updated June 2025
 */
public class EmailMatcher implements FieldMatcherInterface {
  // Cache for match results to avoid redundant calculations
  private static Map<String, Decimal> matchCache = new Map<String, Decimal>();
  private static final Integer MAX_CACHE_SIZE = 1000;
  
  // Known equivalent domains (corporate acquisitions or service rebrandings)
  private static final Map<String, String> EQUIVALENT_DOMAINS = new Map<String, String>{
    'googlemail.com' => 'gmail.com',
    'hotmail.com' => 'outlook.com',
    'live.com' => 'outlook.com',
    'msn.com' => 'outlook.com',
    'yahoo.co.uk' => 'yahoo.com',
    'ymail.com' => 'yahoo.com'
  };
  
  // Common domains for boosting partial matches
  private static final Set<String> COMMON_DOMAINS = new Set<String>{
    'gmail.com', 'yahoo.com', 'hotmail.com', 'outlook.com', 'icloud.com',
    'aol.com', 'protonmail.com', 'mail.com', 'zoho.com', 'gmx.com'
  };
  
  /**
   * Checks if this matcher can handle the specified field
   *
   * @param fieldName API name of the field
   * @return True if this matcher can handle the field
   */
  public Boolean canHandleField(String fieldName) {
    String normalizedFieldName = fieldName.toLowerCase();

    // Handle fields that are likely to contain emails
    return normalizedFieldName.contains('email') ||
      normalizedFieldName.endsWith('email') ||
      normalizedFieldName.equals('email') ||
      normalizedFieldName.contains('e-mail');
  }

  /**
   * Calculates match score between two email values with advanced matching
   *
   * @param email1 First email to compare
   * @param email2 Second email to compare
   * @return Match score (0-100)
   */
  public Decimal calculateMatchScore(String email1, String email2) {
    // Handle null values
    if (String.isBlank(email1) || String.isBlank(email2)) {
      return 0;
    }
    
    // Check cache first - create cache key by alphabetically ordering inputs for consistency
    String cacheKey = email1 < email2 ? 
                      'email:' + email1 + ':' + email2 : 
                      'email:' + email2 + ':' + email1;
    
    if (matchCache.containsKey(cacheKey)) {
      return matchCache.get(cacheKey);
    }

    // Normalize emails
    email1 = normalizeEmail(email1);
    email2 = normalizeEmail(email2);

    // Exact match after normalization
    if (email1 == email2) {
      cacheResult(cacheKey, 100);
      return 100;
    }

    // Split emails into local part and domain
    List<String> parts1 = email1.split('@');
    List<String> parts2 = email2.split('@');

    // Invalid email format
    if (parts1.size() != 2 || parts2.size() != 2) {
      // Fall back to generic matching with lower confidence
      Decimal genericScore = new GenericMatcher().calculateMatchScore(email1, email2) * 0.8;
      cacheResult(cacheKey, genericScore);
      return genericScore;
    }

    String local1 = parts1[0];
    String domain1 = parts1[1];
    String local2 = parts2[0];
    String domain2 = parts2[1];
    
    // Check for domain equivalence (including branded equivalents)
    Boolean domainsEquivalent = areDomainsEquivalent(domain1, domain2);
    
    // Apply special Gmail handling for periods and plus extensions
    if (isGmailDomain(domain1) && isGmailDomain(domain2)) {
      Decimal gmailScore = compareGmailAddresses(local1, local2);
      if (gmailScore > 0) {
        cacheResult(cacheKey, gmailScore);
        return gmailScore;
      }
    }

    // If domains don't match at all, reduce confidence considerably
    if (!domainsEquivalent) {
      // For common domains, we can be more strict as typos are less likely
      if (COMMON_DOMAINS.contains(domain1) || COMMON_DOMAINS.contains(domain2)) {
        // Check for domain typos (levenshtein distance of 1 or 2)
        if (LevenshteinCalculator.distance(domain1, domain2) <= 2) {
          // Possible domain typo, but reduce confidence
          // Continue with local part matching but penalize score
          domainsEquivalent = true;
        } else {
          // Different domains, very low confidence
          Decimal lowScore = calculateTypoScore(local1, local2) * 0.3;
          cacheResult(cacheKey, lowScore);
          return lowScore;
        }
      } else {
        // For less common domains, we can be less strict about domain matching
        // as people might misremember or mistype domain names more often
        if (LevenshteinCalculator.distance(domain1, domain2) <= 3) {
          // Possible domain typo, continue with reduced confidence
          domainsEquivalent = true;
        } else {
          // Different domains, very low confidence
          Decimal lowScore = calculateTypoScore(local1, local2) * 0.3;
          cacheResult(cacheKey, lowScore);
          return lowScore;
        }
      }
    }

    // Exact match on local part with equivalent domains
    if (local1 == local2 && domainsEquivalent) {
      cacheResult(cacheKey, 100);
      return 100;
    }
    
    // Compute match score for local part
    Decimal localPartScore = calculateLocalPartScore(local1, local2);
    
    // Final score calculation with domain boost if domains are exactly the same
    Decimal finalScore = localPartScore;
    if (domain1 == domain2) {
      // Exact domain match gets a slight boost (but can't exceed 100)
      finalScore = Math.min(100, localPartScore + 5);
    } else if (domainsEquivalent) {
      // Equivalent but not exact domains get a smaller boost
      finalScore = Math.min(100, localPartScore + 2);
    }
    
    cacheResult(cacheKey, finalScore);
    return finalScore;
  }
  
  /**
   * Calculate score for local part of email addresses
   * @param local1 First local part
   * @param local2 Second local part
   * @return Match score for local part
   */
  private Decimal calculateLocalPartScore(String local1, String local2) {
    // Check for common email prefix variations
    if (isCommonVariation(local1, local2)) {
      return 95;
    }

    // Check for period-separated versions of the same name
    // e.g., john.doe vs johndoe
    if (local1.replace('.', '') == local2.replace('.', '')) {
      return 95;
    }

    // Check for plus extensions (e.g., email+extension@domain.com)
    if (local1.contains('+') || local2.contains('+')) {
      String base1 = local1.contains('+')
        ? local1.substring(0, local1.indexOf('+'))
        : local1;
      String base2 = local2.contains('+')
        ? local2.substring(0, local2.indexOf('+'))
        : local2;

      if (base1 == base2) {
        return 95;
      }
      
      // Even if the base parts aren't exact, they might be similar
      Decimal baseSimilarity = calculateTypoScore(base1, base2);
      if (baseSimilarity >= 80) {
        return baseSimilarity;
      }
    }

    // Check for typos and misspellings
    Decimal typoScore = calculateTypoScore(local1, local2);
    if (typoScore >= 80) {
      return typoScore;
    }

    // Calculate substring similarity
    if (isSubstringOrCommonPrefix(local1, local2)) {
      return 85;
    }
    
    // Check for number variations (e.g. john1 vs john2)
    if (areNumberVariations(local1, local2)) {
      return 70; // Lower confidence for number variations
    }

    // Use Levenshtein distance for a fallback similarity measure
    return Math.max(0, 100 - (LevenshteinCalculator.distance(local1, local2) * 25));
  }

  /**
   * Normalizes an email address
   *
   * @param email Email to normalize
   * @return Normalized email
   */
  private String normalizeEmail(String email) {
    if (String.isBlank(email)) {
      return '';
    }

    // Convert to lowercase
    String normalizedEmail = email.toLowerCase().trim();

    // Remove any whitespace
    normalizedEmail = normalizedEmail.replaceAll('\\s+', '');
    
    // Fix common typos in domains
    if (normalizedEmail.contains('@')) {
      String domain = normalizedEmail.substring(normalizedEmail.lastIndexOf('@') + 1);
      
      // Fix gmail typos
      if (domain.contains('gmail') && domain != 'gmail.com') {
        if (domain.contains('gamil') || domain.contains('gmial') || 
            domain.contains('gmal') || domain.contains('gmai')) {
          normalizedEmail = normalizedEmail.substring(0, normalizedEmail.lastIndexOf('@') + 1) + 'gmail.com';
        }
      }
      
      // Fix yahoo typos
      if (domain.contains('yahoo') && domain != 'yahoo.com') {
        if (domain.contains('yaho') || domain.contains('yahooo')) {
          normalizedEmail = normalizedEmail.substring(0, normalizedEmail.lastIndexOf('@') + 1) + 'yahoo.com';
        }
      }
    }

    return normalizedEmail;
  }
  
  /**
   * Cache a match result, managing cache size
   * @param key Cache key
   * @param value Score to cache
   */
  private void cacheResult(String key, Decimal value) {
    // Manage cache size - if we're at capacity, remove a random entry
    if (matchCache.size() >= MAX_CACHE_SIZE && !matchCache.containsKey(key)) {
      // Get a key to remove (first one we find)
      String keyToRemove = null;
      for (String cacheKey : matchCache.keySet()) {
        keyToRemove = cacheKey;
        break;
      }
      
      if (keyToRemove != null) {
        matchCache.remove(keyToRemove);
      }
    }
    
    // Add to cache
    matchCache.put(key, value);
  }
  
  /**
   * Check if a domain is Gmail (including variants)
   * @param domain Domain to check
   * @return True if it's a Gmail domain
   */
  private Boolean isGmailDomain(String domain) {
    return domain == 'gmail.com' || domain == 'googlemail.com' || 
           domain.endsWith('.gmail.com');
  }
  
  /**
   * Compare Gmail addresses with special Gmail-specific rules
   * @param local1 First local part
   * @param local2 Second local part
   * @return Match score
   */
  private Decimal compareGmailAddresses(String local1, String local2) {
    // Remove dots (Gmail ignores dots in the local part)
    String noDots1 = local1.replace('.', '');
    String noDots2 = local2.replace('.', '');
    
    // Exact match after removing dots
    if (noDots1 == noDots2) {
      return 100;
    }
    
    // Check for plus extensions after removing dots
    if (noDots1.contains('+') || noDots2.contains('+')) {
      String base1 = noDots1.contains('+') ? noDots1.substring(0, noDots1.indexOf('+')) : noDots1;
      String base2 = noDots2.contains('+') ? noDots2.substring(0, noDots2.indexOf('+')) : noDots2;
      
      // Exact match on base part
      if (base1 == base2) {
        return 100;
      }
      
      // Check for typos in base part
      Decimal baseTypoScore = calculateTypoScore(base1, base2);
      if (baseTypoScore >= 85) {
        return baseTypoScore;
      }
    }
    
    // Not a match by Gmail rules, return 0 to fall back to standard comparison
    return 0;
  }
  
  /**
   * Check if two domains are equivalent (same service)
   * @param domain1 First domain
   * @param domain2 Second domain
   * @return True if domains are equivalent
   */
  private Boolean areDomainsEquivalent(String domain1, String domain2) {
    // Exact match
    if (domain1 == domain2) {
      return true;
    }
    
    // Check known equivalences (e.g., hotmail.com = outlook.com)
    String normalized1 = EQUIVALENT_DOMAINS.containsKey(domain1) ? EQUIVALENT_DOMAINS.get(domain1) : domain1;
    String normalized2 = EQUIVALENT_DOMAINS.containsKey(domain2) ? EQUIVALENT_DOMAINS.get(domain2) : domain2;
    
    return normalized1 == normalized2;
  }
  
  /**
   * Calculate typo similarity score between two strings
   * @param str1 First string
   * @param str2 Second string
   * @return Similarity score accounting for common typos
   */
  private Decimal calculateTypoScore(String str1, String str2) {
    // Quick length check - if length differs significantly, less likely to be a typo
    if (Math.abs(str1.length() - str2.length()) > 2) {
      return LevenshteinCalculator.similarity(str1, str2) * 0.8;
    }
    
    // Check for common keyboard adjacency typos
    Integer adjacentKeyErrors = countAdjacentKeyErrors(str1, str2);
    
    // If strings are same length and have only 1-2 characters different in adjacent positions
    if (str1.length() == str2.length() && adjacentKeyErrors > 0 && adjacentKeyErrors <= 2) {
      // Calculate base similarity, weighting adjacent key errors less harshly
      Decimal baseSimilarity = 100.0 - (adjacentKeyErrors * 10.0);
      
      // Apply length factor - longer strings with few errors are more likely to be typos
      Decimal lengthBoost = Math.min(10, str1.length() / 2.0);
      return Math.min(95, baseSimilarity + lengthBoost);
    }
    
    // Use Levenshtein for other cases but normalize by length
    Integer distance = LevenshteinCalculator.distance(str1, str2);
    Decimal maxLength = Math.max(str1.length(), str2.length());
    
    // For short strings, be more strict
    if (maxLength <= 5) {
      return Math.max(0, 100 - (distance * 25));
    } else {
      // For longer strings, more lenient
      return Math.max(0, 100 - (100.0 * distance / maxLength));
    }
  }
  
  /**
   * Count errors that could be due to adjacent keys on a keyboard
   * @param str1 First string
   * @param str2 Second string
   * @return Number of potential adjacent key errors
   */
  private Integer countAdjacentKeyErrors(String str1, String str2) {
    // Simple implementation - just count differences
    if (str1.length() != str2.length()) {
      return 0;
    }
    
    Integer errorCount = 0;
    for (Integer i = 0; i < str1.length(); i++) {
      if (str1.charAt(i) != str2.charAt(i)) {
        // This is a simplification - ideally would check actual keyboard adjacency
        errorCount++;
      }
    }
    
    return errorCount;
  }
  
  /**
   * Check if local parts are the same except for trailing numbers
   * @param local1 First local part
   * @param local2 Second local part
   * @return True if they differ only by trailing numbers
   */
  private Boolean areNumberVariations(String local1, String local2) {
    // Extract base part (without trailing numbers)
    String base1 = local1.replaceAll('\\d+$', '');
    String base2 = local2.replaceAll('\\d+$', '');
    
    // If base parts match, and both had numbers, they're number variations
    if (base1 == base2 && base1.length() > 0 && 
        base1.length() < local1.length() && base2.length() < local2.length()) {
      return true;
    }
    
    return false;
  }

  /**
   * Checks if two local parts are common variations of each other
   *
   * @param local1 First local part
   * @param local2 Second local part
   * @return True if they are common variations
   */
  private Boolean isCommonVariation(String local1, String local2) {
    // Common variations like first initial + last name
    // e.g., jsmith and johnsmith
    if (local1.length() > 1 && local2.length() > 1) {
      // Check if one starts with the first letter of the other
      if (
        (local1.startsWith(local2.substring(0, 1)) &&
        local1.endsWith(local2.substring(1))) ||
        (local2.startsWith(local1.substring(0, 1)) &&
        local2.endsWith(local1.substring(1)))
      ) {
        return true;
      }

      // Check for first.last vs firstlast
      if (local1.contains('.') || local2.contains('.')) {
        String noDots1 = local1.replace('.', '');
        String noDots2 = local2.replace('.', '');
        if (noDots1 == noDots2) {
          return true;
        }
      }
      
      // Check for common username patterns
      // First initial + last name (e.g., jdoe vs johndoe)
      if (local1.length() > local2.length() && local1.startsWith(local2.substring(0, 1))) {
        // Look for a potential last name part
        for (Integer i = 1; i < local1.length(); i++) {
          if (local1.substring(i).equals(local2.substring(1))) {
            return true;
          }
        }
      } else if (local2.length() > local1.length() && local2.startsWith(local1.substring(0, 1))) {
        // Same check in reverse
        for (Integer i = 1; i < local2.length(); i++) {
          if (local2.substring(i).equals(local1.substring(1))) {
            return true;
          }
        }
      }
    }

    return false;
  }

  /**
   * Checks if one local part is a substring of the other or they share a common prefix
   *
   * @param local1 First local part
   * @param local2 Second local part
   * @return True if one is a substring of the other or they share a common prefix
   */
  private Boolean isSubstringOrCommonPrefix(String local1, String local2) {
    // Check if one is a substring of the other
    if (local1.contains(local2) || local2.contains(local1)) {
      return true;
    }

    // Check for common prefix (at least 4 chars)
    Integer minLength = Math.min(local1.length(), local2.length());
    if (minLength >= 4) {
      Integer commonPrefixLength = 0;
      for (Integer i = 0; i < minLength; i++) {
        if (local1.substring(i, i + 1) == local2.substring(i, i + 1)) {
          commonPrefixLength++;
        } else {
          break;
        }
      }

      // If at least 4 chars match at the beginning, consider it a possible match
      if (commonPrefixLength >= 4) {
        return true;
      }
    }
    
    // Check for common suffix (at least 5 chars) which could be domain migration
    if (minLength >= 5) {
      Integer commonSuffixLength = 0;
      for (Integer i = 1; i <= minLength; i++) {
        if (local1.substring(local1.length() - i, local1.length() - i + 1) == 
            local2.substring(local2.length() - i, local2.length() - i + 1)) {
          commonSuffixLength++;
        } else {
          break;
        }
      }
      
      // If at least 5 chars match at the end, consider it a possible match
      if (commonSuffixLength >= 5) {
        return true;
      }
    }

    return false;
  }
}
