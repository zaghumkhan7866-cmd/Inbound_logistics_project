-- Vendors Dimension
CREATE TABLE dim_vendors (
    vendor_id VARCHAR(50) PRIMARY KEY,
    vendor_name VARCHAR(255),
    origin_country VARCHAR(100)
);

-- Plants Dimension
CREATE TABLE dim_plants (
    plant_code VARCHAR(50) PRIMARY KEY,
    plant_name VARCHAR(255),
    country_code VARCHAR(10)
);

-- Materials Dimension
CREATE TABLE dim_materials (
    material_id VARCHAR(50) PRIMARY KEY,
    material_description TEXT,
    category VARCHAR(100),
    unit_volume_cbm NUMERIC(10, 4)
);
-- SAP Purchase Order Lines
CREATE TABLE sap_purchase_order_lines (
    purchase_order VARCHAR(50),
    po_item VARCHAR(20),
    vendor_id VARCHAR(50),
    plant_code VARCHAR(50),
    material_id VARCHAR(50),
    ordered_qty INT,
    po_created_date DATE,
    requested_delivery_date DATE,
    currency VARCHAR(10),
    unit_price NUMERIC(12, 2),
    PRIMARY KEY (purchase_order, po_item)
);

-- SAP Inbound Deliveries
CREATE TABLE sap_inbound_deliveries (
    inbound_delivery VARCHAR(50),
    ibd_item VARCHAR(20),
    purchase_order VARCHAR(50),
    container_id VARCHAR(50),
    shipped_qty INT,
    planned_ship_date DATE,
    requested_delivery_date DATE,
    PRIMARY KEY (inbound_delivery, ibd_item)
);
-- Ocean Bookings
CREATE TABLE ocean_bookings (
    carrier_booking_number VARCHAR(50) PRIMARY KEY,
    mbol VARCHAR(50),
    cbl VARCHAR(50),
    container_id VARCHAR(50),
    purchase_order VARCHAR(50),
    port_of_loading VARCHAR(50),
    port_of_discharge VARCHAR(50),
    etd_utc TIMESTAMP,
    eta_utc TIMESTAMP,
    vessel_name VARCHAR(100),
    voyage_number VARCHAR(50)
);

-- Ocean Tracking Events
CREATE TABLE ocean_tracking_events (
    event_id VARCHAR(50),
    carrier_booking_number VARCHAR(50),
    container_id VARCHAR(50),
    event_code VARCHAR(50),
    event_classifier VARCHAR(50),
    event_timestamp_utc TIMESTAMP,
    unlocode VARCHAR(20),
    location_name VARCHAR(100),
    transport_mode VARCHAR(50)
);
-- Inland Shipments
CREATE TABLE inland_shipments (
    inland_shipment_id VARCHAR(50) PRIMARY KEY,
    parent_container_id VARCHAR(50),
    purchase_order VARCHAR(50),
    origin_location VARCHAR(100),
    destination_location VARCHAR(100),
    available_at_port_utc TIMESTAMP,
    planned_delivery_utc TIMESTAMP
);

-- Inland Segments
CREATE TABLE inland_segments (
    inland_shipment_id VARCHAR(50),
    segment_sequence INT,
    transport_mode VARCHAR(50),
    equipment_id VARCHAR(50),
    origin_location VARCHAR(100),
    destination_location VARCHAR(100),
    planned_start_utc TIMESTAMP,
    planned_end_utc TIMESTAMP,
    PRIMARY KEY (inland_shipment_id, segment_sequence)
);

-- Inland Tracking Events
CREATE TABLE inland_tracking_events (
    event_id VARCHAR(50) PRIMARY KEY,
    inland_shipment_id VARCHAR(50),
    segment_sequence INT,
    event_type VARCHAR(50),
    event_timestamp_utc TIMESTAMP
);
-- WMS ASN (Advanced Shipment Notice)
CREATE TABLE wms_asn (
    asn_id VARCHAR(50) PRIMARY KEY,
    inbound_delivery VARCHAR(50),
    container_id VARCHAR(50),
    purchase_order VARCHAR(50),
    plant_code VARCHAR(50),
    asn_created_utc TIMESTAMP,
    expected_receipt_utc TIMESTAMP,
    asn_status VARCHAR(50)
);

-- WMS Receipts
CREATE TABLE wms_receipts (
    receipt_id VARCHAR(50) PRIMARY KEY,
    asn_id VARCHAR(50),
    po_item VARCHAR(20),
    material_id VARCHAR(50),
    received_qty INT,
    receipt_timestamp_utc TIMESTAMP,
    inventory_status VARCHAR(50)
);
------------------------------------------------
--Phase 1: All Tables Grain Check & Validation  
-- SAP Purchase Order Lines Grain Check
SELECT 
    COUNT(*) AS total_rows,                                  
    COUNT(DISTINCT purchase_order) AS unique_pos,            
    COUNT(DISTINCT (purchase_order, po_item)) AS unique_po_lines 
FROM sap_purchase_order_lines;

-- SAP Inbound Deliveries Grain Check
SELECT 
    COUNT(*) AS total_rows,                                      
    COUNT(DISTINCT inbound_delivery) AS unique_ibds,             
    COUNT(DISTINCT (inbound_delivery, ibd_item)) AS unique_ibd_lines 
FROM sap_inbound_deliveries;

-- Ocean Bookings Grain Check
SELECT 
    COUNT(*) AS total_rows,                                      
    COUNT(DISTINCT carrier_booking_number) AS unique_bookings,   
    COUNT(DISTINCT container_id) AS unique_containers,           
    COUNT(DISTINCT (carrier_booking_number, container_id)) AS unique_booking_containers 
FROM ocean_bookings;

-- Ocean Tracking Events Grain Check
SELECT 
    COUNT(*) AS total_rows,
    COUNT(DISTINCT event_id) AS unique_events
FROM ocean_tracking_events;

-- Inland Shipments Grain Check
SELECT 
    COUNT(*) AS total_rows,                  
    COUNT(DISTINCT inland_shipment_id) AS unique_shipments 
FROM inland_shipments;

-- Inland Segments Grain Check
SELECT 
    COUNT(*) AS total_rows,
    COUNT(DISTINCT (inland_shipment_id, segment_sequence)) AS unique_segments
FROM inland_segments;

-- Inland Tracking Events Grain Check
SELECT 
    COUNT(*) AS total_rows,
    COUNT(DISTINCT event_id) AS unique_events
FROM inland_tracking_events;

-- WMS ASN Grain Check
SELECT 
    COUNT(*) AS total_rows,
    COUNT(DISTINCT asn_id) AS unique_asns
FROM wms_asn;

-- WMS Receipts Grain Check
SELECT 
    COUNT(*) AS total_rows,
    COUNT(DISTINCT receipt_id) AS unique_receipts
FROM wms_receipts;

-- Dimensions Grain Check
SELECT 'dim_vendors' AS table_name, COUNT(*) AS rows, COUNT(DISTINCT vendor_id) AS unique_key FROM dim_vendors
UNION ALL
SELECT 'dim_plants', COUNT(*), COUNT(DISTINCT plant_code) FROM dim_plants
UNION ALL
SELECT 'dim_materials', COUNT(*), COUNT(DISTINCT material_id) FROM dim_materials;

--Phase 2: Relationship Discovery & Reconciliation Queries

-- Check container match between SAP Inbound Deliveries and Ocean Bookings
SELECT 
    COUNT(DISTINCT s.container_id) AS sap_containers,           -- Total containers in SAP
    COUNT(DISTINCT o.container_id) AS ocean_containers,         -- Total containers in Ocean bookings
    COUNT(DISTINCT CASE WHEN s.container_id = o.container_id THEN s.container_id END) AS matched_containers -- Containers matched across both systems
FROM sap_inbound_deliveries s
FULL OUTER JOIN ocean_bookings o 
    ON s.container_id = o.container_id;

	-- Calculate reconciliation metrics between SAP and Ocean containers
SELECT 
    COUNT(DISTINCT s.container_id) AS sap_containers,           -- Total unique containers in SAP inbound deliveries
    COUNT(DISTINCT o.container_id) AS ocean_containers,         -- Total unique containers in Ocean bookings
    COUNT(DISTINCT CASE WHEN s.container_id = o.container_id THEN s.container_id END) AS matched_containers, -- Common across both systems
    (COUNT(DISTINCT s.container_id) - COUNT(DISTINCT CASE WHEN s.container_id = o.container_id THEN s.container_id END)) AS sap_only_containers, -- Containers existing only in SAP
    (COUNT(DISTINCT o.container_id) - COUNT(DISTINCT CASE WHEN s.container_id = o.container_id THEN s.container_id END)) AS ocean_only_containers  -- Containers existing only in Ocean
FROM sap_inbound_deliveries s
FULL OUTER JOIN ocean_bookings o 
    ON s.container_id = o.container_id;

	-- Reconcile SAP Inbound Deliveries with WMS ASNs and Receipts
SELECT 
    ibd.inbound_delivery,                                      -- SAP Inbound Delivery number
    ibd.container_id,                                          -- Container ID
    asn.asn_id,                                                -- WMS ASN (Advanced Shipment Notice) ID
    asn.expected_receipt_utc,                                  -- Expected receipt timestamp
    wr.receipt_timestamp_utc,                                  -- Actual arrival timestamp at warehouse
    wr.received_qty,                                           -- Actual physical quantity received
    wr.inventory_status                                        -- Status (e.g., 'Available', 'Hold')
FROM sap_inbound_deliveries ibd
LEFT JOIN wms_asn asn 
    ON ibd.inbound_delivery = asn.inbound_delivery
LEFT JOIN wms_receipts wr 
    ON asn.asn_id = wr.asn_id;

-- Using EXCEPT & INTERSECT (Logistics Engineering Operators)

-- INTERSECT: Containers that exist in both systems (SAP and Ocean)

SELECT container_id FROM sap_inbound_deliveries
INTERSECT
SELECT container_id FROM ocean_bookings;

-- EXCEPT: Containers that exist only in Ocean bookings but not in SAP

SELECT container_id FROM ocean_bookings
EXCEPT
SELECT container_id FROM sap_inbound_deliveries;

--Phase 3: Shipment Spine
-- Create a base shipment spine connecting SAP PO lines and Inbound Deliveries
SELECT 
    po.purchase_order,                  -- Purchase Order number
    po.po_item,                         -- PO Line item number
    po.vendor_id,                       -- Vendor ID
    po.plant_code,                      -- Plant Code
    po.material_id,                     -- Material ID
    po.ordered_qty,                     -- Ordered Quantity
    ibd.inbound_delivery,               -- Inbound Delivery number
    ibd.container_id,                   -- Container ID
    ibd.shipped_qty                     -- Shipped Quantity
FROM sap_purchase_order_lines po
LEFT JOIN sap_inbound_deliveries ibd
    ON po.purchase_order = ibd.purchase_order
    AND po.po_item = ibd.ibd_item;

-- Extend the shipment spine to include Ocean Bookings data via container_id
SELECT 
    po.purchase_order,                  -- Purchase Order number
    po.po_item,                         -- PO Line item number
    po.vendor_id,                       -- Vendor ID
    po.plant_code,                      -- Plant Code
    po.material_id,                     -- Material ID
    po.ordered_qty,                     -- Ordered Quantity
    ibd.inbound_delivery,               -- Inbound Delivery number
    ibd.container_id,                   -- Container ID
    ibd.shipped_qty,                    -- Shipped Quantity
    ob.carrier_booking_number,          -- Ocean Carrier Booking Number
    ob.vessel_name,                     -- Vessel Name
    ob.port_of_loading,                 -- Port of Loading
    ob.port_of_discharge                -- Port of Discharge
FROM sap_purchase_order_lines po
LEFT JOIN sap_inbound_deliveries ibd
    ON po.purchase_order = ibd.purchase_order
    AND po.po_item = ibd.ibd_item
LEFT JOIN ocean_bookings ob
    ON ibd.container_id = ob.container_id;
	
-- Phase 4: Calculate ocean transit days between ETD and ETA for each container
SELECT 
    carrier_booking_number,                                    -- Booking Number
    container_id,                                              -- Container ID
    etd_utc,                                                   -- Departure Date & Time (Estimated Time of Departure)
    eta_utc,                                                   -- Arrival Date & Time (Estimated Time of Arrival)
    EXTRACT(DAY FROM (eta_utc - etd_utc)) AS ocean_transit_days -- Total days taken in ocean transit
FROM ocean_bookings;

--Pivot ocean tracking events to analyze actual milestone timestamps and transit latency
SELECT 
    container_id,
    MIN(CASE WHEN event_code = 'GATE_IN' THEN event_timestamp_utc END) AS gate_in_at,
    MIN(CASE WHEN event_code = 'VESSEL_DEPARTURE' THEN event_timestamp_utc END) AS vessel_departure_at,
    MIN(CASE WHEN event_code = 'VESSEL_ARRIVAL' THEN event_timestamp_utc END) AS vessel_arrival_at,
    MIN(CASE WHEN event_code = 'DISCHARGED' THEN event_timestamp_utc END) AS discharged_at,
    ROUND(
        EXTRACT(EPOCH FROM (
            MIN(CASE WHEN event_code = 'VESSEL_ARRIVAL' THEN event_timestamp_utc END) -
            MIN(CASE WHEN event_code = 'VESSEL_DEPARTURE' THEN event_timestamp_utc END)
        )) / 86400.0, 2 -- calculating days.
    ) AS actual_ocean_transit_days
FROM ocean_tracking_events
GROUP BY container_id;

--Calculate Port Dwell Hours between DISCHARGED and GATE_OUT events
SELECT 
    container_id,
    MIN(CASE WHEN event_code = 'DISCHARGED' THEN event_timestamp_utc END) AS discharged_at,
    MIN(CASE WHEN event_code = 'GATE_OUT' THEN event_timestamp_utc END) AS gate_out_at,
    ROUND(
        EXTRACT(EPOCH FROM (
            MIN(CASE WHEN event_code = 'GATE_OUT' THEN event_timestamp_utc END) -
            MIN(CASE WHEN event_code = 'DISCHARGED' THEN event_timestamp_utc END)
        )) / 3600.0, 2 --calculating hours.
    ) AS port_dwell_hours
FROM ocean_tracking_events
GROUP BY container_id
ORDER BY port_dwell_hours DESC;

-- Phase 5: Inland Transport Segmentation & Equipment Mapping
SELECT 
    iship.inland_shipment_id,                              -- Inland Shipment ID
    iship.parent_container_id,                             -- Parent Container ID
    iship.origin_location AS shipment_origin,              -- Shipment Origin Location (e.g., Port)
    iship.destination_location AS shipment_destination,    -- Shipment Destination Location (e.g., DC Warehouse)
    iseg.segment_sequence,                                 -- Segment Sequence (Step 1 for Dray, Step 2 for OTR/Rail)
    iseg.transport_mode,                                   -- Mode of transport (DRAY, RAIL, OTR)
    iseg.equipment_id                                      -- Equipment / Trailer ID used in this segment
FROM inland_shipments iship
LEFT JOIN inland_segments iseg 
    ON iship.inland_shipment_id = iseg.inland_shipment_id;

--Inland Transportation Route Modeling using Window Functions (LAG & LEAD)
SELECT 
    iship.inland_shipment_id,
    iship.parent_container_id,
    iseg.segment_sequence,
    
    -- Previous transport mode using LAG()
    LAG(iseg.transport_mode) OVER (
        PARTITION BY iseg.inland_shipment_id 
        ORDER BY iseg.segment_sequence
    ) AS prev_transport_mode,
    
    -- Current transport mode
    iseg.transport_mode AS current_transport_mode,
    
    -- Next transport mode using LEAD()
    LEAD(iseg.transport_mode) OVER (
        PARTITION BY iseg.inland_shipment_id 
        ORDER BY iseg.segment_sequence
    ) AS next_transport_mode,
    
    iseg.equipment_id,
    iseg.origin_location,
    iseg.destination_location
FROM inland_shipments iship
JOIN inland_segments iseg 
    ON iship.inland_shipment_id = iseg.inland_shipment_id
ORDER BY iship.inland_shipment_id, iseg.segment_sequence;
	
	-- Phase 6: Transport-Unit Relationships (Ocean Container to Inland Trailer Transload Mapping)
SELECT 
    iship.parent_container_id AS ocean_container,         -- Parent Ocean Container (Arrived via ocean transit)
    iseg.transport_mode,                                   -- Transport mode (e.g., DRAY, RAIL, OTR)
    iseg.equipment_id AS trailer_equipment,                -- Child Trailer ID (Equipment where goods were transloaded)
    iseg.segment_sequence,                                 -- Segment sequence number
    iseg.origin_location,                                  -- Segment starting location
    iseg.destination_location                              -- Segment ending location
FROM inland_shipments iship
JOIN inland_segments iseg 
    ON iship.inland_shipment_id = iseg.inland_shipment_id
WHERE iseg.transport_mode != 'OCEAN';                      -- Filter out ocean segments to focus on inland transport

-- Phase 6: Transport-Unit Relationships & Transload Bridge Model
SELECT 
    iship.parent_container_id AS parent_equipment,           -- Ocean Container (Parent)
    iseg.equipment_id AS child_equipment,                     -- Trailer / Domestic Equipment (Child)
    
    -- Detect relationship type based on transload logic
    CASE 
        WHEN iship.parent_container_id != iseg.equipment_id 
             AND iseg.transport_mode IN ('OTR', 'RAIL') 
        THEN 'TRANSLOAD_TO_TRAILER'
        
        WHEN iship.parent_container_id = iseg.equipment_id 
             AND iseg.transport_mode = 'DRAY' 
        THEN 'DIRECT_CONTAINER_DRAY'
        
        ELSE 'EQUIPMENT_ASSIGNMENT'
    END AS relationship_type,
    
    -- Lifecycle effective dates / timestamps
    iseg.planned_start_utc AS effective_from,                  -- Effective Start Timestamp
    iseg.planned_end_utc AS effective_to                       -- Effective End Timestamp

FROM inland_shipments iship
JOIN inland_segments iseg 
    ON iship.inland_shipment_id = iseg.inland_shipment_id
WHERE iseg.equipment_id IS NOT NULL;

-- Phase 7: Reconcile SAP Ordered Quantity vs Warehouse Received Quantity
-- (Reconcile SAP Ordered Quantity vs WMS Received Quantity at PO & Item Level)

WITH aggregated_receipts AS (
    SELECT 
        asn.purchase_order,
        wr.po_item,
        SUM(wr.received_qty) AS total_received_qty
    FROM wms_asn asn
    JOIN wms_receipts wr ON asn.asn_id = wr.asn_id
    GROUP BY asn.purchase_order, wr.po_item
)
SELECT 
    po.purchase_order,                                         -- SAP PO Number
    po.po_item,                                                -- PO Line Item
    po.material_id,                                            -- Material ID
    po.ordered_qty,                                            -- Total Ordered Quantity in SAP
    COALESCE(ar.total_received_qty, 0) AS total_received_qty,   -- Actual Received Quantity for this Item
    (po.ordered_qty - COALESCE(ar.total_received_qty, 0)) AS short_qty, -- Shortage
    ROUND(
        (COALESCE(ar.total_received_qty, 0)::NUMERIC / NULLIF(po.ordered_qty, 0)) * 100.0, 
        2
    ) AS fill_rate_pct                                         -- Fill Rate Percentage
FROM sap_purchase_order_lines po
LEFT JOIN aggregated_receipts ar 
    ON po.purchase_order = ar.purchase_order 
    AND po.po_item = ar.po_item;

	-- Phase 7: Warehouse Reconciliation with Pre-Aggregated CTEs at PO Item Grain
WITH aggregated_shipped AS (
    -- Step 1: Pre-aggregate shipped quantities from SAP Inbound Deliveries
    SELECT 
        purchase_order,
        ibd_item,
        SUM(shipped_qty) AS total_shipped_qty
    FROM sap_inbound_deliveries
    GROUP BY purchase_order, ibd_item
),
aggregated_receipts AS (
    -- Step 2: Pre-aggregate received quantities from WMS Receipts mapped via ASN
    SELECT 
        asn.purchase_order,
        wr.po_item,
        SUM(wr.received_qty) AS total_received_qty
    FROM wms_asn asn
    JOIN wms_receipts wr ON asn.asn_id = wr.asn_id
    GROUP BY asn.purchase_order, wr.po_item
)
SELECT 
    po.purchase_order,
    po.po_item,
    po.material_id,
    po.ordered_qty,
    
    -- Shipped & Received Quantities
    COALESCE(ash.total_shipped_qty, 0) AS shipped_qty,
    COALESCE(arec.total_received_qty, 0) AS received_qty,
    
    -- Calculated Discrepancies & Metrics
    GREATEST(0, po.ordered_qty - COALESCE(arec.total_received_qty, 0)) AS open_qty,
    
    CASE 
        WHEN COALESCE(arec.total_received_qty, 0) < po.ordered_qty 
        THEN po.ordered_qty - COALESCE(arec.total_received_qty, 0)
        ELSE 0 
    END AS short_qty,
    
    CASE 
        WHEN COALESCE(arec.total_received_qty, 0) > po.ordered_qty 
        THEN COALESCE(arec.total_received_qty, 0) - po.ordered_qty
        ELSE 0 
    END AS over_qty,
    
    ROUND(
        (COALESCE(arec.total_received_qty, 0)::NUMERIC / NULLIF(po.ordered_qty, 0)) * 100.0, 
        2
    ) AS fill_rate_pct
    
FROM sap_purchase_order_lines po
LEFT JOIN aggregated_shipped ash 
    ON po.purchase_order = ash.purchase_order 
    AND po.po_item = ash.ibd_item
LEFT JOIN aggregated_receipts arec 
    ON po.purchase_order = arec.purchase_order 
    AND po.po_item = arec.po_item;

-- Phase 8: ETA & Delay Analysis and Shipment Performance Classification

WITH shipment_actuals AS (
    -- Pre-aggregate actual warehouse receipt dates per Purchase Order
    SELECT 
        asn.purchase_order,
        MAX(wr.receipt_timestamp_utc) AS actual_receipt_timestamp
    FROM wms_asn asn
    JOIN wms_receipts wr ON asn.asn_id = wr.asn_id
    GROUP BY asn.purchase_order
)
SELECT 
    po.purchase_order,
    po.material_id,
    po.requested_delivery_date,
    iship.planned_delivery_utc AS planned_inland_delivery,
    sa.actual_receipt_timestamp AS actual_warehouse_receipt,
    
    -- Shipment Performance Classification Logic
    CASE 
        -- 1. Already Received and On/Before Requested Date
        WHEN sa.actual_receipt_timestamp IS NOT NULL 
             AND sa.actual_receipt_timestamp::DATE <= po.requested_delivery_date 
        THEN 'ON_TIME'
        
        -- 2. Already Received but After Requested Date (Late delivery received)
        WHEN sa.actual_receipt_timestamp IS NOT NULL 
             AND sa.actual_receipt_timestamp::DATE > po.requested_delivery_date 
        THEN 'LATE'
        
        -- 3. Not yet received, but planned/current delivery date has passed requested date -> AT RISK
        WHEN iship.planned_delivery_utc::DATE > po.requested_delivery_date 
             AND sa.actual_receipt_timestamp IS NULL 
        THEN 'AT_RISK'
        
        -- 4. Today / Current Date has passed requested date and still not received -> LATE
        WHEN CURRENT_DATE > po.requested_delivery_date 
             AND sa.actual_receipt_timestamp IS NULL 
        THEN 'LATE'
        
        -- 5. Otherwise ON TRACK
        ELSE 'ON_TRACK'
    END AS shipment_status

FROM sap_purchase_order_lines po
LEFT JOIN inland_shipments iship 
    ON po.purchase_order = iship.purchase_order
LEFT JOIN shipment_actuals sa 
    ON po.purchase_order = sa.purchase_order;

--Phase 9: Exception Detection & Data Quality Layer
--1. PO Without Inbound Delivery (PO_WITHOUT_IBD)
--Checks for Purchase Orders against which no inbound delivery has been created:

SELECT purchase_order, material_id, 'PO_WITHOUT_IBD' AS exception_type
FROM sap_purchase_order_lines po
WHERE NOT EXISTS (
    SELECT 1 
    FROM sap_inbound_deliveries ibd 
    WHERE ibd.purchase_order = po.purchase_order 
      AND ibd.ibd_item = po.po_item
);

--2. Container Without Booking / Events (CONTAINER_WITHOUT_BOOKING)
--Checks if a container exists in an inbound delivery but has no tracking records in ocean events:

SELECT inbound_delivery, container_id, 'CONTAINER_WITHOUT_BOOKING' AS exception_type
FROM sap_inbound_deliveries ibd
WHERE container_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 
      FROM ocean_tracking_events ote 
      WHERE ote.container_id = ibd.container_id
  );

  --3. Arrival Without Departure (ARRIVAL_WITHOUT_DEPARTURE & GATE_OUT_WITHOUT_DISCHARGE)
--Uses window functions or event sequence checks on ocean tracking events to detect anomalies
--(e.g., container gated-out without discharge, or departure logged before arrival):

WITH ordered_events AS (
    SELECT 
        container_id,
        event_code,
        event_timestamp_utc,
        LAG(event_code) OVER (PARTITION BY container_id ORDER BY event_timestamp_utc) AS prev_event_code
    FROM ocean_tracking_events
)
SELECT container_id, event_code, prev_event_code, 'INVALID_EVENT_SEQUENCE' AS exception_type
FROM ordered_events
WHERE (event_code = 'GATE_OUT' AND prev_event_code != 'DISCHARGED')
   OR (event_code = 'DISCHARGED' AND prev_event_code != 'VESSEL_ARRIVAL');

--4. Over-Receipt / Short-Receipt (OVER_RECEIPT / SHORT_RECEIPT)
--Compares warehouse receipts against SAP PO ordered quantity to identify discrepancies:
WITH po_receipt_summary AS (
    SELECT 
        po.purchase_order,
        po.po_item,
        po.ordered_qty,
        COALESCE(SUM(wr.received_qty), 0) AS received_qty
    FROM sap_purchase_order_lines po
    LEFT JOIN wms_asn asn ON po.purchase_order = asn.purchase_order
    LEFT JOIN wms_receipts wr ON asn.asn_id = wr.asn_id AND po.po_item = wr.po_item
    GROUP BY po.purchase_order, po.po_item, po.ordered_qty
)
SELECT 
    purchase_order,
    po_item,
    ordered_qty,
    received_qty,
    CASE 
        WHEN received_qty > ordered_qty THEN 'OVER_RECEIPT'
        WHEN received_qty < ordered_qty THEN 'SHORT_RECEIPT'
        ELSE 'MATCHED'
    END AS exception_type
FROM po_receipt_summary
WHERE received_qty != ordered_qty;

-- Phase 10: Final Inbound Logistics KPI Aggregation Mart for Dashboard Reporting
SELECT 
    DATE_TRUNC('month', po.requested_delivery_date)::DATE AS reporting_month,
    
    -- Container & Shipment Volume Metrics
    COUNT(DISTINCT ibd.container_id) AS total_inbound_containers,
    COUNT(DISTINCT po.purchase_order) AS total_purchase_orders,
    
    -- Warehouse & Fulfillment Metrics
    ROUND(AVG(po.ordered_qty), 2) AS avg_ordered_qty,
    
    -- Fill Rate & Discrepancies (% calculation)
    ROUND(
        (SUM(COALESCE(wr.received_qty, 0))::NUMERIC / NULLIF(SUM(po.ordered_qty), 0)) * 100.0, 
        2
    ) AS overall_po_fill_rate_pct,
    
    -- Short Receipt Percentage (Fixed COUNT syntax)
    ROUND(
        (SUM(CASE WHEN COALESCE(wr.received_qty, 0) < po.ordered_qty THEN 1 ELSE 0 END)::NUMERIC 
         / NULLIF(COUNT(*), 0)) * 100.0, 
        2
    ) AS short_receipt_pct

FROM sap_purchase_order_lines po
LEFT JOIN sap_inbound_deliveries ibd 
    ON po.purchase_order = ibd.purchase_order 
    AND po.po_item = ibd.ibd_item
LEFT JOIN wms_asn asn 
    ON ibd.inbound_delivery = asn.inbound_delivery
LEFT JOIN wms_receipts wr 
    ON asn.asn_id = wr.asn_id 
    AND po.po_item = wr.po_item
GROUP BY DATE_TRUNC('month', po.requested_delivery_date)::DATE
ORDER BY reporting_month DESC;

-- Phase 10: Advanced Inbound Logistics Dashboard & KPI Mart
WITH shipment_pipeline AS (
    SELECT 
        po.purchase_order,
        po.vendor_id,
        ibd.container_id,
        ibd.inbound_delivery,
        iship.origin_location,
        iship.destination_location,
        po.requested_delivery_date,
        iship.planned_delivery_utc AS planned_inland_delivery,
        COALESCE(wr.receipt_timestamp_utc, NULL) AS actual_warehouse_receipt,
        
        -- Container Pipeline Status Classification
        CASE 
            WHEN wr.receipt_timestamp_utc IS NOT NULL THEN 'RECEIVED'
            WHEN iship.inland_shipment_id IS NOT NULL THEN 'IN_INLAND_TRANSIT'
            WHEN ibd.container_id IS NOT NULL THEN 'AT_PORT'
            ELSE 'ON_OCEAN'
        END AS container_status
    FROM sap_purchase_order_lines po
    LEFT JOIN sap_inbound_deliveries ibd 
        ON po.purchase_order = ibd.purchase_order AND po.po_item = ibd.ibd_item
    LEFT JOIN inland_shipments iship 
        ON po.purchase_order = iship.purchase_order
    LEFT JOIN wms_asn asn 
        ON ibd.inbound_delivery = asn.inbound_delivery
    LEFT JOIN wms_receipts wr 
        ON asn.asn_id = wr.asn_id AND po.po_item = wr.po_item
)
SELECT 
    -- 1. Container Pipeline Breakdown (Counts)
    COUNT(DISTINCT CASE WHEN container_status = 'ON_OCEAN' THEN container_id END) AS containers_on_ocean,
    COUNT(DISTINCT CASE WHEN container_status = 'AT_PORT' THEN container_id END) AS containers_at_port,
    COUNT(DISTINCT CASE WHEN container_status = 'IN_INLAND_TRANSIT' THEN container_id END) AS containers_in_inland_transit,
    COUNT(DISTINCT CASE WHEN container_status = 'RECEIVED' THEN container_id END) AS containers_received,
    
    -- 2. Performance & SLA Metrics
    COUNT(DISTINCT CASE WHEN actual_warehouse_receipt IS NOT NULL AND actual_warehouse_receipt::DATE <= requested_delivery_date THEN purchase_order END) * 100.0 / NULLIF(COUNT(DISTINCT CASE WHEN actual_warehouse_receipt IS NOT NULL THEN purchase_order END), 0) AS on_time_delivery_pct,
    
    COUNT(DISTINCT CASE WHEN actual_warehouse_receipt IS NOT NULL AND actual_warehouse_receipt::DATE > requested_delivery_date THEN purchase_order END) AS late_shipment_count

FROM shipment_pipeline;

--1. Top Delayed Vendors (Vendors with the highest number of late shipments)

SELECT 
    po.vendor_id,
    COUNT(DISTINCT po.purchase_order) AS late_shipment_count
FROM sap_purchase_order_lines po
JOIN wms_asn asn ON po.purchase_order = asn.purchase_order
JOIN wms_receipts wr ON asn.asn_id = wr.asn_id AND po.po_item = wr.po_item
WHERE wr.receipt_timestamp_utc::DATE > po.requested_delivery_date
GROUP BY po.vendor_id
ORDER BY late_shipment_count DESC
LIMIT 5;

--2. Top Delayed Lanes (Origin to destination routes experiencing the highest delay counts)

SELECT 
    iship.origin_location,
    iship.destination_location,
    COUNT(DISTINCT iship.inland_shipment_id) AS delayed_shipment_count
FROM inland_shipments iship
JOIN sap_purchase_order_lines po ON iship.purchase_order = po.purchase_order
JOIN wms_asn asn ON po.purchase_order = asn.purchase_order
JOIN wms_receipts wr ON asn.asn_id = wr.asn_id AND po.po_item = wr.po_item
WHERE wr.receipt_timestamp_utc::DATE > po.requested_delivery_date
GROUP BY iship.origin_location, iship.destination_location
ORDER BY delayed_shipment_count DESC
LIMIT 5;