library;

import '../../../core/utils/json_cast.dart';

enum WorkbenchMode { sandbox, liveBackend }

class LineItemModel {
  final String name;
  final int qty;
  final int unitPriceCents;
  final int subtotalCents;

  const LineItemModel({
    required this.name,
    required this.qty,
    required this.unitPriceCents,
    required this.subtotalCents,
  });

  factory LineItemModel.fromJson(Map<String, dynamic> json) {
    return LineItemModel(
      name: asString(json['name']) ?? '',
      qty: asInt(json['qty']) ?? 1,
      unitPriceCents: asInt(json['unit_price_cents']) ?? 0,
      subtotalCents: asInt(json['subtotal_cents']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'qty': qty,
    'unit_price_cents': unitPriceCents,
    'subtotal_cents': subtotalCents,
  };
}

class ExtractedTicketModel {
  final String docType;
  final String customerName;
  final String unitAddress;
  final String contactPhone;
  final String issueSummary;
  final String priority;
  final int laborFeeCents;
  final int partsFeeCents;
  final int totalFeeCents;
  final bool customerSigned;
  final double confidence;
  final List<LineItemModel> lineItems;
  final String rawNotes;

  const ExtractedTicketModel({
    required this.docType,
    required this.customerName,
    required this.unitAddress,
    required this.contactPhone,
    required this.issueSummary,
    required this.priority,
    required this.laborFeeCents,
    required this.partsFeeCents,
    required this.totalFeeCents,
    required this.customerSigned,
    required this.confidence,
    required this.lineItems,
    required this.rawNotes,
  });

  factory ExtractedTicketModel.fromJson(Map<String, dynamic> json) {
    return ExtractedTicketModel(
      docType: asString(json['doc_type']) ?? 'repair_ticket',
      customerName: asString(json['customer_name']) ?? '',
      unitAddress: asString(json['unit_address']) ?? '',
      contactPhone: asString(json['contact_phone']) ?? '',
      issueSummary: asString(json['issue_summary']) ?? '',
      priority: asString(json['priority']) ?? 'NORMAL',
      laborFeeCents: asInt(json['labor_fee_cents']) ?? 0,
      partsFeeCents: asInt(json['parts_fee_cents']) ?? 0,
      totalFeeCents: asInt(json['total_fee_cents']) ?? 0,
      customerSigned: asBool(json['customer_signed']) ?? false,
      confidence: asDouble(json['confidence']) ?? 0.9,
      lineItems: asJsonList(json['line_items'], LineItemModel.fromJson),
      rawNotes: asString(json['raw_notes']) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'doc_type': docType,
    'customer_name': customerName,
    'unit_address': unitAddress,
    'contact_phone': contactPhone,
    'issue_summary': issueSummary,
    'priority': priority,
    'labor_fee_cents': laborFeeCents,
    'parts_fee_cents': partsFeeCents,
    'total_fee_cents': totalFeeCents,
    'customer_signed': customerSigned,
    'confidence': confidence,
    'line_items': lineItems.map((e) => e.toJson()).toList(),
    'raw_notes': rawNotes,
  };

  ExtractedTicketModel copyWith({
    String? customerName,
    String? unitAddress,
    String? contactPhone,
    String? issueSummary,
    String? priority,
    int? laborFeeCents,
    int? partsFeeCents,
    int? totalFeeCents,
    bool? customerSigned,
    String? rawNotes,
  }) {
    return ExtractedTicketModel(
      docType: docType,
      customerName: customerName ?? this.customerName,
      unitAddress: unitAddress ?? this.unitAddress,
      contactPhone: contactPhone ?? this.contactPhone,
      issueSummary: issueSummary ?? this.issueSummary,
      priority: priority ?? this.priority,
      laborFeeCents: laborFeeCents ?? this.laborFeeCents,
      partsFeeCents: partsFeeCents ?? this.partsFeeCents,
      totalFeeCents: totalFeeCents ?? this.totalFeeCents,
      customerSigned: customerSigned ?? this.customerSigned,
      confidence: confidence,
      lineItems: lineItems,
      rawNotes: rawNotes ?? this.rawNotes,
    );
  }
}

class GuardFlagModel {
  final String code;
  final String severity;
  final String? field;
  final String message;

  const GuardFlagModel({
    required this.code,
    required this.severity,
    this.field,
    required this.message,
  });

  bool get isBlocker => severity == 'blocker';

  factory GuardFlagModel.fromJson(Map<String, dynamic> json) {
    return GuardFlagModel(
      code: asString(json['code']) ?? 'UNKNOWN',
      severity: asString(json['severity']) ?? 'blocker',
      field: asString(json['field']),
      message: asString(json['message']) ?? '',
    );
  }
}

class NodeTraceModel {
  final String node;
  final String status;
  final double durationMs;
  final String detail;
  final String timestamp;

  const NodeTraceModel({
    required this.node,
    required this.status,
    required this.durationMs,
    required this.detail,
    required this.timestamp,
  });

  factory NodeTraceModel.fromJson(Map<String, dynamic> json) {
    return NodeTraceModel(
      node: asString(json['node']) ?? '',
      status: asString(json['status']) ?? 'completed',
      durationMs: asDouble(json['duration_ms']) ?? 0.0,
      detail: asString(json['detail']) ?? '',
      timestamp: asString(json['timestamp']) ?? '',
    );
  }
}

class FixtureModel {
  final String fixtureId;
  final String title;
  final String category;
  final String docType;
  final String tenantId;
  final String description;
  final String documentText;
  final ExtractedTicketModel? previewTicket;

  const FixtureModel({
    required this.fixtureId,
    required this.title,
    required this.category,
    required this.docType,
    required this.tenantId,
    required this.description,
    required this.documentText,
    this.previewTicket,
  });

  factory FixtureModel.fromJson(Map<String, dynamic> json) {
    return FixtureModel(
      fixtureId: asString(json['fixture_id']) ?? '',
      title: asString(json['title']) ?? '',
      category: asString(json['category']) ?? 'clean_auto',
      docType: asString(json['doc_type']) ?? 'repair_ticket',
      tenantId: asString(json['tenant_id']) ?? 'synthetic-prop-01',
      description: asString(json['description']) ?? '',
      documentText: asString(json['document_text']) ?? '',
      previewTicket: asJsonObject(
        json['preview_ticket'],
        ExtractedTicketModel.fromJson,
      ),
    );
  }
}

class RunSnapshotModel {
  final String threadId;
  final String docId;
  final String docTitle;
  final String tenantId;
  final String status; // 'completed' | 'interrupted' | 'rejected'
  final ExtractedTicketModel? extractedTicket;
  final ExtractedTicketModel? finalTicket;
  final List<GuardFlagModel> guardFlags;
  final String? workOrderId;
  final bool idempotentReused;
  final String? evalCaseId;
  final String reviewerNote;
  final List<NodeTraceModel> nodeTrace;
  final String updatedAt;

  const RunSnapshotModel({
    required this.threadId,
    required this.docId,
    required this.docTitle,
    required this.tenantId,
    required this.status,
    this.extractedTicket,
    this.finalTicket,
    required this.guardFlags,
    this.workOrderId,
    required this.idempotentReused,
    this.evalCaseId,
    required this.reviewerNote,
    required this.nodeTrace,
    required this.updatedAt,
  });

  bool get isInterrupted => status == 'interrupted';
  bool get isCompleted => status == 'completed';
  bool get isRejected => status == 'rejected';

  factory RunSnapshotModel.fromJson(Map<String, dynamic> json) {
    return RunSnapshotModel(
      threadId: asString(json['thread_id']) ?? '',
      docId: asString(json['doc_id']) ?? '',
      docTitle: asString(json['doc_title']) ?? '',
      tenantId: asString(json['tenant_id']) ?? '',
      status: asString(json['status']) ?? 'completed',
      extractedTicket: asJsonObject(
        json['extracted_ticket'],
        ExtractedTicketModel.fromJson,
      ),
      finalTicket: asJsonObject(
        json['final_ticket'],
        ExtractedTicketModel.fromJson,
      ),
      guardFlags: asJsonList(json['guard_flags'], GuardFlagModel.fromJson),
      workOrderId: asString(json['work_order_id']),
      idempotentReused: asBool(json['idempotent_reused']) ?? false,
      evalCaseId: asString(json['eval_case_id']),
      reviewerNote: asString(json['reviewer_note']) ?? '',
      nodeTrace: asJsonList(json['node_trace'], NodeTraceModel.fromJson),
      updatedAt: asString(json['updated_at']) ?? '',
    );
  }
}

class WorkOrderModel {
  final String workOrderId;
  final String threadId;
  final String docId;
  final String idempotencyKey;
  final String payloadFingerprint;
  final ExtractedTicketModel ticket;
  final int replayHits;
  final String createdAt;

  const WorkOrderModel({
    required this.workOrderId,
    required this.threadId,
    required this.docId,
    required this.idempotencyKey,
    required this.payloadFingerprint,
    required this.ticket,
    required this.replayHits,
    required this.createdAt,
  });

  factory WorkOrderModel.fromJson(Map<String, dynamic> json) {
    return WorkOrderModel(
      workOrderId: asString(json['work_order_id']) ?? '',
      threadId: asString(json['thread_id']) ?? '',
      docId: asString(json['doc_id']) ?? '',
      idempotencyKey: asString(json['idempotency_key']) ?? '',
      payloadFingerprint: asString(json['payload_fingerprint']) ?? '',
      ticket:
          asJsonObject(json['ticket'], ExtractedTicketModel.fromJson) ??
          const ExtractedTicketModel(
            docType: 'repair_ticket',
            customerName: '',
            unitAddress: '',
            contactPhone: '',
            issueSummary: '',
            priority: 'NORMAL',
            laborFeeCents: 0,
            partsFeeCents: 0,
            totalFeeCents: 0,
            customerSigned: false,
            confidence: 0,
            lineItems: [],
            rawNotes: '',
          ),
      replayHits: asInt(json['replay_hits']) ?? 0,
      createdAt: asString(json['created_at']) ?? '',
    );
  }
}

class FieldDiffModel {
  final String field;
  final String rawValue;
  final String correctedValue;

  const FieldDiffModel({
    required this.field,
    required this.rawValue,
    required this.correctedValue,
  });

  factory FieldDiffModel.fromJson(Map<String, dynamic> json) {
    return FieldDiffModel(
      field: asString(json['field']) ?? '',
      rawValue: asString(json['raw_value']) ?? '',
      correctedValue: asString(json['corrected_value']) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'field': field,
    'raw_value': rawValue,
    'corrected_value': correctedValue,
  };
}

class EvalCaseModel {
  final String caseId;
  final String threadId;
  final String docId;
  final String docType;
  final List<String> guardCodes;
  final List<FieldDiffModel> fieldDiffs;
  final ExtractedTicketModel rawExtraction;
  final ExtractedTicketModel expectedTruth;
  final String reviewerNote;
  final String createdAt;

  const EvalCaseModel({
    required this.caseId,
    required this.threadId,
    required this.docId,
    required this.docType,
    required this.guardCodes,
    required this.fieldDiffs,
    required this.rawExtraction,
    required this.expectedTruth,
    required this.reviewerNote,
    required this.createdAt,
  });

  factory EvalCaseModel.fromJson(Map<String, dynamic> json) {
    final codesRaw = json['guard_codes'];
    final codes = codesRaw is List
        ? codesRaw
              .map((e) => asString(e) ?? '')
              .where((s) => s.isNotEmpty)
              .toList()
        : const <String>[];
    const fallbackTicket = ExtractedTicketModel(
      docType: 'repair_ticket',
      customerName: '',
      unitAddress: '',
      contactPhone: '',
      issueSummary: '',
      priority: 'NORMAL',
      laborFeeCents: 0,
      partsFeeCents: 0,
      totalFeeCents: 0,
      customerSigned: false,
      confidence: 0,
      lineItems: [],
      rawNotes: '',
    );
    return EvalCaseModel(
      caseId: asString(json['case_id']) ?? '',
      threadId: asString(json['thread_id']) ?? '',
      docId: asString(json['doc_id']) ?? '',
      docType: asString(json['doc_type']) ?? 'repair_ticket',
      guardCodes: codes,
      fieldDiffs: asJsonList(json['field_diffs'], FieldDiffModel.fromJson),
      rawExtraction:
          asJsonObject(json['raw_extraction'], ExtractedTicketModel.fromJson) ??
          fallbackTicket,
      expectedTruth:
          asJsonObject(json['expected_truth'], ExtractedTicketModel.fromJson) ??
          fallbackTicket,
      reviewerNote: asString(json['reviewer_note']) ?? '',
      createdAt: asString(json['created_at']) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'case_id': caseId,
    'thread_id': threadId,
    'doc_id': docId,
    'doc_type': docType,
    'guard_codes': guardCodes,
    'field_diffs': fieldDiffs.map((d) => d.toJson()).toList(),
    'raw_extraction': rawExtraction.toJson(),
    'expected_truth': expectedTruth.toJson(),
    'reviewer_note': reviewerNote,
    'created_at': createdAt,
  };
}

class WorkbenchViewData {
  final WorkbenchMode mode;
  final String backendBaseUrl;
  final List<FixtureModel> fixtures;
  final String selectedFixtureId;
  final List<RunSnapshotModel> runs;
  final String? activeThreadId;
  final List<WorkOrderModel> workOrders;
  final List<EvalCaseModel> evalCases;
  final String exportedJsonl;

  const WorkbenchViewData({
    required this.mode,
    required this.backendBaseUrl,
    required this.fixtures,
    required this.selectedFixtureId,
    required this.runs,
    this.activeThreadId,
    required this.workOrders,
    required this.evalCases,
    required this.exportedJsonl,
  });

  FixtureModel? get selectedFixture {
    for (final f in fixtures) {
      if (f.fixtureId == selectedFixtureId) return f;
    }
    return fixtures.isNotEmpty ? fixtures.first : null;
  }

  RunSnapshotModel? get activeRun {
    if (activeThreadId == null) return null;
    for (final r in runs) {
      if (r.threadId == activeThreadId) return r;
    }
    return null;
  }

  WorkbenchViewData copyWith({
    WorkbenchMode? mode,
    String? backendBaseUrl,
    List<FixtureModel>? fixtures,
    String? selectedFixtureId,
    List<RunSnapshotModel>? runs,
    String? activeThreadId,
    List<WorkOrderModel>? workOrders,
    List<EvalCaseModel>? evalCases,
    String? exportedJsonl,
  }) {
    return WorkbenchViewData(
      mode: mode ?? this.mode,
      backendBaseUrl: backendBaseUrl ?? this.backendBaseUrl,
      fixtures: fixtures ?? this.fixtures,
      selectedFixtureId: selectedFixtureId ?? this.selectedFixtureId,
      runs: runs ?? this.runs,
      activeThreadId: activeThreadId ?? this.activeThreadId,
      workOrders: workOrders ?? this.workOrders,
      evalCases: evalCases ?? this.evalCases,
      exportedJsonl: exportedJsonl ?? this.exportedJsonl,
    );
  }
}
