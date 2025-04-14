import { LightningElement, api } from "lwc";

export default class DuplicationFinder extends LightningElement {
  @api height = 800;
  @api useSafeArea = false;

  // Internal properties
  isLoading = false;
  selectedObject = "";
  error = false;
  errorMessage = "";

  // Check if we're in a tab vs app page
  get isInTab() {
    return (
      document.location.href && document.location.href.includes("/lightning/n/")
    );
  }

  connectedCallback() {
    // Special handling for tabs - use fixed values for better compatibility
    if (this.isInTab) {
      // When in a tab, use more reliable default settings
      this.height = 800;
      this.useSafeArea = false;
    }

    // Set styling hooks for the Lightning container
    document.documentElement.style.setProperty(
      "--lwc-sizeMedium",
      `${this.height}px`
    );
    document.documentElement.style.setProperty("--lwc-heightFull", "100%");

    // Fix viewport issues
    setTimeout(() => {
      // Apply styles to container based on properties
      const containerElement = this.template.querySelector(".container");
      if (containerElement) {
        // Always set minHeight regardless of other settings
        containerElement.style.minHeight = `${this.height}px`;

        // Apply safe area padding only when explicitly enabled and not in a tab
        if (this.useSafeArea === true && !this.isInTab) {
          // Set safe area padding
          containerElement.style.paddingTop = "env(safe-area-inset-top)";
          containerElement.style.paddingBottom = "env(safe-area-inset-bottom)";
          containerElement.style.paddingLeft = "env(safe-area-inset-left)";
          containerElement.style.paddingRight = "env(safe-area-inset-right)";
        }
      }
    }, 100);
  }

  disconnectedCallback() {
    // Clean up styling hooks
    document.documentElement.style.removeProperty("--lwc-sizeMedium");
    document.documentElement.style.removeProperty("--lwc-heightFull");
  }

  renderedCallback() {
    // Additional layout adjustments if needed after rendering
    const container = this.template.querySelector(".container");
    if (container) {
      // Ensure container takes up full height available
      container.style.minHeight = `${this.height}px`;
    }
  }

  // Event handler for object selection
  handleObjectChange(event) {
    this.selectedObject = event.target.value;
  }

  // Event handler for find duplicates button
  handleFindDuplicates() {
    if (!this.selectedObject) {
      this.error = true;
      this.errorMessage = "Please select an object first";
      // Auto-dismiss error after 3 seconds
      setTimeout(() => {
        this.error = false;
      }, 3000);
      return;
    }

    this.isLoading = true;

    // Simulate finding duplicates for demo purposes
    setTimeout(() => {
      this.isLoading = false;
    }, 2000);
  }

  // Event handler for health check button
  handleHealthCheck() {
    this.isLoading = true;

    // Simulate health check for demo purposes
    setTimeout(() => {
      this.isLoading = false;
    }, 1500);
  }
}
