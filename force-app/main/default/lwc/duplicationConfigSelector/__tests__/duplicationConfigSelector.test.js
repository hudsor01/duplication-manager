import { createElement } from 'lwc';
import DuplicationConfigSelector from 'c/duplicationConfigSelector';
import getActiveSettings from '@salesforce/apex/DuplicateRecordController.getActiveSettings';
import getFieldsForObject from '@salesforce/apex/DuplicateRecordController.getFieldsForObject';

// Mock Apex methods
jest.mock(
    '@salesforce/apex/DuplicateRecordController.getActiveSettings',
    () => {
        return {
            default: jest.fn()
        };
    },
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/DuplicateRecordController.getFieldsForObject',
    () => {
        return {
            default: jest.fn()
        };
    },
    { virtual: true }
);

// Mock store
jest.mock('c/duplicationStore', () => {
    return {
        default: {
            getState: jest.fn().mockReturnValue({
                selectedConfiguration: null,
                recentConfigurations: []
            }),
            dispatch: jest.fn()
        },
        duplicationStore: {
            actions: {
                SELECT_CONFIGURATION: 'SELECT_CONFIGURATION',
                SET_CONFIGURATIONS: 'SET_CONFIGURATIONS',
                ADD_ERROR: 'ADD_ERROR'
            }
        }
    };
}, { virtual: true });

// Mock message service
jest.mock('c/duplicationMessageService', () => {
    return {
        subscribeToChannel: jest.fn(),
        unsubscribeFromChannel: jest.fn()
    };
}, { virtual: true });

// Sample data for tests
const mockConfigurations = [
    {
        Id: '1',
        DeveloperName: 'Account_Standard',
        MasterLabel: 'Account Standard',
        ObjectApiName: 'Account',
        MatchFields: 'Name, Phone, Email, BillingStreet',
        MasterRecordStrategy: 'MostComplete',
        BatchSize: 200,
        MatchThreshold: 75,
        Description: 'Standard account matching configuration'
    },
    {
        Id: '2',
        DeveloperName: 'Contact_Standard',
        MasterLabel: 'Contact Standard',
        ObjectApiName: 'Contact',
        MatchFields: 'LastName, FirstName, Email, Phone',
        MasterRecordStrategy: 'MostComplete',
        BatchSize: 200,
        MatchThreshold: 75,
        Description: 'Standard contact matching configuration'
    }
];

const mockFieldsForObject = {
    objectApiName: 'Account',
    fieldGroups: [
        {
            label: 'Standard Fields',
            fields: [
                { apiName: 'Name', label: 'Name', type: 'String', isCustom: false },
                { apiName: 'Phone', label: 'Phone', type: 'Phone', isCustom: false },
                { apiName: 'Email', label: 'Email', type: 'Email', isCustom: false },
                { apiName: 'BillingStreet', label: 'Billing Street', type: 'String', isCustom: false }
            ]
        },
        {
            label: 'Custom Fields',
            fields: [
                { apiName: 'CustomField__c', label: 'Custom Field', type: 'String', isCustom: true }
            ]
        }
    ]
};

describe('c-duplication-config-selector', () => {
    let element;

    beforeEach(() => {
        // Reset mocks
        getActiveSettings.default.mockResolvedValue(mockConfigurations);
        getFieldsForObject.default.mockResolvedValue(mockFieldsForObject);
        
        // Create component
        element = createElement('c-duplication-config-selector', {
            is: DuplicationConfigSelector
        });
        document.body.appendChild(element);
    });

    afterEach(() => {
        // Remove element from DOM
        if (document.body.contains(element)) {
            document.body.removeChild(element);
        }
        // Reset any values set in localStorage
        jest.clearAllMocks();
    });

    it('shows loading spinner when loading', async () => {
        // Component starts with isLoading = true
        const spinner = element.shadowRoot.querySelector('lightning-spinner');
        expect(spinner).not.toBeNull();
    });

    it('calls getActiveSettings on initialization', () => {
        expect(getActiveSettings.default).toHaveBeenCalled();
    });

    it('shows configuration dropdown when configurations are loaded', async () => {
        // Wait for any asynchronous DOM updates
        await Promise.resolve();
        await Promise.resolve();
        
        const combobox = element.shadowRoot.querySelector('lightning-combobox');
        expect(combobox).not.toBeNull();
    });

    it('shows customize field selection checkbox when configuration is selected', async () => {
        // Set selected configuration
        const store = require('c/duplicationStore').default;
        store.getState.mockReturnValue({
            selectedConfiguration: mockConfigurations[0],
            recentConfigurations: []
        });
        
        // Wait for any asynchronous DOM updates
        await Promise.resolve();
        await Promise.resolve();
        
        // Find the checkbox
        const customizeCheckbox = element.shadowRoot.querySelector('lightning-input[type="checkbox"]');
        expect(customizeCheckbox).not.toBeNull();
        expect(customizeCheckbox.label).toBe('Customize Field Selection');
    });

    it('displays custom field selection panel when checkbox is checked', async () => {
        // Set selected configuration
        const store = require('c/duplicationStore').default;
        store.getState.mockReturnValue({
            selectedConfiguration: mockConfigurations[0],
            recentConfigurations: []
        });
        
        // Wait for any asynchronous DOM updates
        await Promise.resolve();
        await Promise.resolve();
        
        // Find and click the checkbox
        const customizeCheckbox = element.shadowRoot.querySelector('lightning-input[type="checkbox"]');
        customizeCheckbox.checked = true;
        customizeCheckbox.dispatchEvent(new CustomEvent('change', { detail: { checked: true } }));
        
        // Wait for any asynchronous DOM updates
        await Promise.resolve();
        await Promise.resolve();
        
        // Verify fields are loaded
        expect(getFieldsForObject.default).toHaveBeenCalledWith({ objectApiName: 'Account' });
        
        // Should show field selection panel
        const fieldPanel = element.shadowRoot.querySelector('.slds-scrollable');
        expect(fieldPanel).not.toBeNull();
    });
});