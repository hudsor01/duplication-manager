/**
 * @description Class for determining date ranges for statistics queries
 * @author Richard Hudson
 * @date 2025-04-11
 */
public class DRSCDate {
  /**
   * @description Static method for determining the start date based on the time range
   *
   * @param timeRange String identifying the time range (TODAY, YESTERDAY, etc.)
   * @return Date The start date for the range
   */
  @AuraEnabled
  public static Date getStartDateForRange(String timeRange) {
    Date today = Date.today();

    if (String.isBlank(timeRange)) {
      return today.addDays(-30); // Default to last 30 days
    }

    switch on timeRange {
      when 'TODAY' {
        return today;
      }
      when 'YESTERDAY' {
        return today.addDays(-1);
      }
      when 'THIS_WEEK' {
        // Calculate days since the beginning of the week
        // Date doesn't have dayOfWeek in all API versions
        Integer currentDayNum = today.day();
        Integer offset = Math.mod(currentDayNum, 7); // Approximate calculation
        return today.addDays(-offset);
      }
      when 'LAST_7_DAYS' {
        return today.addDays(-7);
      }
      when 'THIS_MONTH' {
        // First day of current month
        return Date.newInstance(today.year(), today.month(), 1);
      }
      when 'LAST_MONTH' {
        // First day of previous month
        Integer lastMonth = today.month() - 1;
        Integer yearOfLastMonth = today.year();

        if (lastMonth == 0) {
          lastMonth = 12;
          yearOfLastMonth -= 1;
        }

        return Date.newInstance(yearOfLastMonth, lastMonth, 1);
      }
      when 'LAST_30_DAYS' {
        return today.addDays(-30);
      }
      when 'THIS_YEAR' {
        // First day of current year
        return Date.newInstance(today.year(), 1, 1);
      }
      when 'LAST_YEAR' {
        // First day of previous year
        return Date.newInstance(today.year() - 1, 1, 1);
      }
      when 'ALL_TIME' {
        return null; // No date filter
      }
      when else {
        return today.addDays(-30); // Default to last 30 days
      }
    }
  }
}
