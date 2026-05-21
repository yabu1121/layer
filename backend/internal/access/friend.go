// Package access は「誰がどのデータを見られるか」の可視性判定を集約する。
// require.md §6.2「友達以外への露出ゼロ」を Go 側で保証するための土台。
package access

import "gorm.io/gorm"

// IsFriend は viewerID と ownerID が accepted な友達関係にあるかを 1 クエリで判定する。
// 友達関係は方向を持たないため、requester/receiver のどちらの並びでも accepted なら true。
// 自分自身（viewerID == ownerID）は友達ではないため false を返す。
// model.md §5.1 の is_friend(viewer, owner) と同じセマンティクス。
func IsFriend(db *gorm.DB, viewerID, ownerID string) (bool, error) {
	if viewerID == ownerID {
		return false, nil
	}
	var ok bool
	err := db.Raw(`select exists (
		select 1 from friendships
		where status = 'accepted'
		  and ((requester_id = ? and receiver_id = ?)
		    or (requester_id = ? and receiver_id = ?))
	)`, viewerID, ownerID, ownerID, viewerID).Scan(&ok).Error
	return ok, err
}
