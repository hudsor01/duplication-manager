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
  
  // Store resize handler reference
  _resizeHandler = null;
  _resizeTimeout = null;
  
  connectedCallback() {
    // Add resize listener for viewport adjustments
    this._resizeHandler = this.handleResize.bind(this);
    window.addEventListener('resize', this._resizeHandler, {passive: true});
  }
  
  disconnectedCallback() {
    // Clean up resize listener
    if (this._resizeHandler) {
      window.removeEventListener('resize', this._resizeHandler);
      this._resizeHandler = null;
    }
    
    // Clear any pending animation frames
    if (this._resizeTimeout) {
      window.cancelAnimationFrame(this._resizeTimeout);
      this._resizeTimeout = null;
    }
  }
  
  /**
   * Handle window resize events with throttling
   */
  handleResize() {
    // Use requestAnimationFrame to avoid too many updates
    if (this._resizeTimeout) {
      window.cancelAnimationFrame(this._resizeTimeout);
    }
    
    this._resizeTimeout = window.requestAnimationFrame(() => {
      // Update container height only
      this.updateContainerHeight();
    });
  }
  
  /**
   * Update container height only - no other DOM manipulation
   */
  updateContainerHeight() {
    try {
      const container = this.template.querySelector('.container');
      if (container) {
        container.style.minHeight = `${window.innerHeight}px`;
      }
    } catch (error) {
      // Silent error handling
    }
  }
}