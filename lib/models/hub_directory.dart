// Models for the public library directory (ADR-015).
//
// Plain Dart data classes that mirror the Rust FFI types
// (FrbDirectoryConfig, FrbHubProfile, FrbHubFollow) without coupling
// the rest of the app to the generated flutter_rust_bridge types.

import '../src/rust/api/frb.dart' as frb;

// ---------------------------------------------------------------------------
// DirectoryConfig
// ---------------------------------------------------------------------------

/// Local hub directory configuration stored in SQLite (singleton row).
class DirectoryConfig {
  final String nodeId;
  final bool isListed;
  final bool requiresApproval;
  final String acceptFrom;

  const DirectoryConfig({
    required this.nodeId,
    required this.isListed,
    required this.requiresApproval,
    required this.acceptFrom,
  });

  factory DirectoryConfig.fromFrb(frb.FrbDirectoryConfig f) => DirectoryConfig(
        nodeId: f.nodeId,
        isListed: f.isListed,
        requiresApproval: f.requiresApproval,
        acceptFrom: f.acceptFrom,
      );
}

// ---------------------------------------------------------------------------
// HubProfile
// ---------------------------------------------------------------------------

/// A library profile from the public hub directory.
class HubProfile {
  final String nodeId;
  final String displayName;
  final String? description;
  final int bookCount;
  final String? locationCountry;
  final bool requiresApproval;
  final String? lastSeenAt;

  const HubProfile({
    required this.nodeId,
    required this.displayName,
    this.description,
    required this.bookCount,
    this.locationCountry,
    required this.requiresApproval,
    this.lastSeenAt,
  });

  factory HubProfile.fromFrb(frb.FrbHubProfile f) => HubProfile(
        nodeId: f.nodeId,
        displayName: f.displayName,
        description: f.description,
        bookCount: f.bookCount,
        locationCountry: f.locationCountry,
        requiresApproval: f.requiresApproval,
        lastSeenAt: f.lastSeenAt,
      );
}

// ---------------------------------------------------------------------------
// HubFollow
// ---------------------------------------------------------------------------

/// A follow relationship between two libraries in the hub directory.
class HubFollow {
  final int id;
  final String followerNodeId;
  final String followedNodeId;

  /// One of: "pending", "active", "rejected", "blocked"
  final String status;
  final String createdAt;
  final String? resolvedAt;

  const HubFollow({
    required this.id,
    required this.followerNodeId,
    required this.followedNodeId,
    required this.status,
    required this.createdAt,
    this.resolvedAt,
  });

  factory HubFollow.fromFrb(frb.FrbHubFollow f) => HubFollow(
        id: f.id,
        followerNodeId: f.followerNodeId,
        followedNodeId: f.followedNodeId,
        status: f.status,
        createdAt: f.createdAt,
        resolvedAt: f.resolvedAt,
      );

  bool get isPending => status == 'pending';
  bool get isActive => status == 'active';
}
