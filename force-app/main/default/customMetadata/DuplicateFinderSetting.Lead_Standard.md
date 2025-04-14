<?xml version="1.0" encoding="UTF-8" ?>

<CustomMetadata
xmlns="http://soap.sforce.com/2006/04/metadata"
xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
xmlns:xsd="http://www.w3.org/2001/XMLSchema"

>

    <label>Lead Standard</label>
    <protected>false</protected>
    <values>
        <field>BatchSize__c</field>
        <value xsi:type="xsd:double">200.0</value>
    </values>
    <values>
        <field>IsActive__c</field>
        <value xsi:type="xsd:boolean">true</value>
    </values>
    <values>
        <field>MasterRecordStrategy__c</field>
        <value xsi:type="xsd:string">MostComplete</value>
    </values>
    <values>
        <field>MatchFields__c</field>
        <value xsi:type="xsd:string">Email,Phone,Company,LastName,FirstName</value>
    </values>
    <values>
        <field>SObject_API_Name__c</field>
        <value xsi:type="xsd:string">Lead</value>
    </values>

</CustomMetadata>
