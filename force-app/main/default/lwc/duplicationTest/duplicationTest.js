import { LightningElement, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { MESSAGE_TYPES } from "c/duplicationConstants";
import {
  subscribeToChannel,
  unsubscribeFromChannel,
  sendMessage
} from "c/duplicationMessageService";

/**
 * Test component for verifying functionality
 */
export default class DuplicationTest extends LightningElement {
  @track testMessage = "UI Setup Successfully";
  @track subscription = null;
  @track receivedMessages = [];
  @track uiStatus = "ready";

  connectedCallback() {
    // Removed console.log
    // Subscribe to message channel
    this.subscription = subscribeToChannel(this.handleMessage.bind(this));
  }

  disconnectedCallback() {
    // Unsubscribe from channel
    if (this.subscription) {
      unsubscribeFromChannel(this.subscription);
    }
  }

  handleMessage(message) {
    // Store received message
    this.receivedMessages.push({
      type: message.type,
      timestamp: new Date().toISOString(),
      payload: JSON.stringify(message.payload || {})
    });
  }

  handleClick() {
    // Test message sending
    sendMessage(MESSAGE_TYPES.TOAST_NOTIFICATION, {
      title: "Test",
      message: "Message service is working!",
      variant: "success"
    });

    this.dispatchEvent(
      new ShowToastEvent({
        title: "Success",
        message: "The component is working correctly!",
        variant: "success"
      })
    );
  }

  // Test view change to verify tab switching
  handleTestView() {
    sendMessage(MESSAGE_TYPES.VIEW_CHANGE, {
      view: "dashboard",
      action: "switch"
    });
  }
}
