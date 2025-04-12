import { LightningElement, api } from "lwc";

export default class DuplicationDashboardCard extends LightningElement {
  @api cardTitle;
  @api iconName = "standard:record_lookup";
}
