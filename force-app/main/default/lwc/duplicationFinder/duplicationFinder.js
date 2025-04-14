import { LightningElement, api } from "lwc";

/**
 * DuplicationFinder is now just a wrapper component that uses duplicationContainer
 * This allows us to maintain compatibility with existing metadata configuration
 * while using the enhanced duplicationContainer component
 */
export default class DuplicationFinder extends LightningElement {
  // Height API property to pass through
  @api height = 800;

  // Safe area API property to pass through
  @api useSafeArea = false;
  
  // Use a getter to always return true for internal use
  get internalUseSafeArea() {
    return true;
  }
  
  connectedCallback() {
    // Make sure we fully support Safari viewport
    this.ensureSafariSupport();
  }
  
  renderedCallback() {
    // Apply Safari-specific handling again after rendering
    this.ensureSafariSupport();
  }
  
  // Add Safari-specific handling to work around viewport issues
  ensureSafariSupport() {
    try {
      const container = this.template.querySelector('.container');
      if (container) {
        // Make sure we apply full viewport height
        const viewportHeight = window.innerHeight;
        container.style.minHeight = `${viewportHeight}px`;
        
        // Add Safari-specific scrolling
        container.style.webkitOverflowScrolling = 'touch';
      }
    } catch (error) {
      // Handle gracefully, no need to log
    }
  }
}
