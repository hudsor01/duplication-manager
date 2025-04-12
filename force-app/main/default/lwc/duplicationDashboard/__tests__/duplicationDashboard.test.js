import { createElement } from "lwc";
import DuplicationDashboard from "c/duplicationDashboard";
import { registerApexTestWireAdapter } from "@salesforce/sfdx-lwc-jest";
import getDetailedStatistics from "@salesforce/apex/DRSCDetailed.getDetailedStatistics";

// Register the Apex wire adapter
const getDetailedStatisticsAdapter = registerApexTestWireAdapter(
  getDetailedStatistics,
);

// Mock the store
jest.mock("c/duplicationStore", () => {
  return {
    default: {
      getState: jest.fn(() => ({
        isLoading: false,
        statistics: {
          totalDuplicates: 100,
          totalMerged: 75,
          byObject: {
            Account: {
              totalDuplicates: 60,
              totalMerged: 45,
            },
            Contact: {
              totalDuplicates: 40,
              totalMerged: 30,
            },
          },
          recentMerges: [
            {
              id: "001",
              objectApiName: "Account",
              configName: "Standard",
              count: 5,
              isDryRun: false,
              timestamp: "2025-05-01T12:00:00Z",
            },
            {
              id: "002",
              objectApiName: "Contact",
              configName: "Standard",
              count: 10,
              isDryRun: true,
              timestamp: "2025-04-28T10:00:00Z",
            },
          ],
        },
      })),
      dispatch: jest.fn(),
      subscribe: jest.fn(() => jest.fn()),
    },
    DuplicationStore: {
      actions: {
        SET_LOADING: "SET_LOADING",
        UPDATE_STATISTICS: "UPDATE_STATISTICS",
        INVALIDATE_CACHE: "INVALIDATE_CACHE",
        ADD_ERROR: "ADD_ERROR",
      },
    },
  };
});

// Mock the message service
jest.mock("c/duplicationMessageService", () => {
  return {
    subscribeToChannel: jest.fn(() => "subscription-id"),
    unsubscribeFromChannel: jest.fn(),
    sendMessage: jest.fn(),
    MESSAGE_TYPES: {
      STORE_UPDATED: "store.updated",
      STORE_SECTION_UPDATED: "store.section.updated",
      REFRESH_STATISTICS: "refresh.statistics",
      TIME_RANGE_CHANGED: "time.range.changed",
      JOB_COMPLETED: "job.completed",
      STATISTICS_LOADING: "statistics.loading",
      STATISTICS_LOADED: "statistics.loaded",
      STATISTICS_LOAD_ERROR: "statistics.load.error",
      REFRESH_STARTED: "refresh.started",
      ERROR_OCCURRED: "error.occurred",
    },
  };
});

// Mock the loadScript function
jest.mock("lightning/platformResourceLoader", () => {
  return {
    loadScript: jest.fn(() => Promise.resolve()),
  };
});

// Sample data for tests
const MOCK_STATISTICS = {
  totalDuplicates: 120,
  totalMerged: 80,
  mergeRate: 0.67,
  byObject: {
    Account: {
      totalDuplicates: 70,
      totalMerged: 50,
    },
    Contact: {
      totalDuplicates: 50,
      totalMerged: 30,
    },
  },
  recentMerges: [
    {
      id: "001",
      objectApiName: "Account",
      configName: "Standard",
      count: 5,
      isDryRun: false,
      timestamp: "2025-05-01T12:00:00Z",
    },
  ],
  timeRange: "LAST_30_DAYS",
};

describe("c-duplication-dashboard", () => {
  let element;

  // Helper function that creates the dashboard component
  const createDashboard = () => {
    element = createElement("c-duplication-dashboard", {
      is: DuplicationDashboard,
    });
    document.body.appendChild(element);

    // Create a mock Chart constructor to simulate chart.js
    if (!window.Chart) {
      window.Chart = function (ctx, config) {
        this.ctx = ctx;
        this.config = config;
        this.data = config.data;
        this.destroy = jest.fn();
        this.update = jest.fn();
        this.resize = jest.fn();
      };
    }

    return element;
  };

  afterEach(() => {
    // Clean up after each test
    if (element) {
      document.body.removeChild(element);
      element = null;
    }

    // Reset mocks
    jest.clearAllMocks();
  });

  it("renders statistics cards when data is available", () => {
    // Create component
    createDashboard();

    // Emit data from the wire adapter
    getDetailedStatisticsAdapter.emit(MOCK_STATISTICS);

    // Return a promise to wait for any asynchronous DOM updates
    return Promise.resolve().then(() => {
      // Verify statistics are displayed
      const statsCards = element.shadowRoot.querySelectorAll(".stats-card");
      expect(statsCards.length).toBe(3);

      // Should show the correct number of duplicates
      const duplicatesValue = element.shadowRoot.querySelector(
        ".stats-card.primary .stats-value",
      );
      expect(duplicatesValue.textContent).toContain("120");
    });
  });

  it("shows loading spinner when isLoading is true", () => {
    // Create component
    element = createDashboard();

    // Set loading state
    element.isLoading = true;

    // Return a promise to wait for any asynchronous DOM updates
    return Promise.resolve().then(() => {
      // Verify loading spinner is showing
      const spinner = element.shadowRoot.querySelector("lightning-spinner");
      expect(spinner).not.toBeNull();
    });
  });

  it("shows error message when hasError is true", () => {
    // Create component
    element = createDashboard();

    // Set error state
    element.error = {
      message: "Test Error",
      details: "This is a test error",
      timestamp: new Date().toISOString(),
    };

    // Return a promise to wait for any asynchronous DOM updates
    return Promise.resolve().then(() => {
      // Verify error message is showing
      const errorMessage = element.shadowRoot.querySelector(".error-container");
      expect(errorMessage).not.toBeNull();
      expect(errorMessage.textContent).toContain("Test Error");
      expect(errorMessage.textContent).toContain("This is a test error");
    });
  });

  it("displays empty state when no statistics available", () => {
    // Create component
    element = createDashboard();

    // Set empty statistics
    element.statistics = {
      totalDuplicates: 0,
      totalMerged: 0,
      byObject: {},
      recentMerges: [],
    };

    // Return a promise to wait for any asynchronous DOM updates
    return Promise.resolve().then(() => {
      // Verify empty state messages are shown
      const emptyStates = element.shadowRoot.querySelectorAll(".empty-state");
      expect(emptyStates.length).toBeGreaterThan(0);

      const firstEmptyState = emptyStates[0];
      expect(firstEmptyState.textContent).toContain(
        "No duplicate statistics available yet",
      );
    });
  });

  it("properly formats trend indicators", () => {
    // Create component
    element = createDashboard();

    // Set statistics with trend data
    element.statistics = {
      totalDuplicates: 120,
      totalMerged: 80,
    };

    // Set previous period data for trend calculation
    element.lastPeriodStats = {
      totalDuplicates: 100,
      totalMerged: 70,
      mergeRate: 0.7,
    };

    // Return a promise to wait for any asynchronous DOM updates
    return Promise.resolve().then(() => {
      // Check computed getters for trend calculations
      expect(element.duplicatesTrendValue).toBeCloseTo(0.2); // 20% increase
      expect(element.isDuplicateTrendPositive).toBe(true);
      expect(element.duplicatesTrendIcon).toBe("utility:arrowup");
      expect(element.duplicatesTrendClass).toContain("trend-up");

      expect(element.mergesTrendValue).toBeCloseTo(0.143, 2); // ~14.3% increase
      expect(element.isMergesTrendPositive).toBe(true);
      expect(element.mergesTrendIcon).toBe("utility:arrowup");
      expect(element.mergesTrendClass).toContain("trend-up");
    });
  });

  it("sanitizes error messages properly", () => {
    // Create component
    element = createDashboard();

    // Test sanitization of sensitive data
    const testCases = [
      {
        input: "Error with token=abc123xyz",
        expected: "Error with token=[REDACTED]",
      },
      {
        input: "Password:secret123",
        expected: "Password=[REDACTED]",
      },
      {
        input: "API key=sk_test_12345",
        expected: "key=[REDACTED]",
      },
      {
        input:
          "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c",
        expected: "Bearer [REDACTED]",
      },
    ];

    testCases.forEach((testCase) => {
      expect(element.sanitizeErrorMessage(testCase.input)).toBe(
        testCase.expected,
      );
    });
  });
});
