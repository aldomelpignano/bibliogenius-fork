import 'network_member.dart';
import 'hub_directory.dart';

/// Filter for the unified network list.
enum LibraryFilter { all, nearby, following, borrowers }

/// A unified view of a remote library, regardless of how we're connected to it.
///
/// A library can be:
/// - A direct peer (P2P, E2EE, real-time book requests)
/// - A hub follow (catalog browsing via the hub, async)
/// - Both at once (same library_uuid / node_id)
class LibraryRelation {
  final String nodeId;
  final String? _displayName;

  /// P2P connection from the peers table. Null if hub-follow only.
  final NetworkMember? peer;

  /// Hub follow relationship. Null if peer only.
  final HubFollow? follow;

  const LibraryRelation({
    required this.nodeId,
    String? displayName,
    this.peer,
    this.follow,
  }) : _displayName = displayName;

  bool get isPeer => peer != null;
  bool get isFollowing => follow != null;

  /// Display name: explicit > peer customDisplayName > peer name > truncated node_id.
  String get name =>
      _displayName ??
      peer?.displayName ??
      (nodeId.length >= 8 ? '…${nodeId.substring(nodeId.length - 8)}' : nodeId);

  /// Whether the display name has been customized by the user.
  bool get hasCustomName =>
      _displayName != null ||
      (peer?.customDisplayName != null && peer!.customDisplayName!.isNotEmpty);

  /// Can browse the catalog (active follow or any peer connection).
  bool get canBrowseCatalog =>
      (follow?.isActive ?? false) || isPeer;

  /// Can send real-time book requests (needs a peer connection).
  bool get canRequestBooks => isPeer;

  /// Follow is pending approval.
  bool get followPending => follow?.isPending ?? false;

  LibraryRelation withDisplayName(String name) => LibraryRelation(
        nodeId: nodeId,
        displayName: name,
        peer: peer,
        follow: follow,
      );

  LibraryRelation withFollow(HubFollow f) => LibraryRelation(
        nodeId: nodeId,
        displayName: _displayName,
        peer: peer,
        follow: f,
      );
}
