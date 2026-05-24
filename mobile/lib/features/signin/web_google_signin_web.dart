import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

/// Web の Google サインイン。GIS の公式ボタンを描画し、サインインで得た
/// ID トークンを [onIdToken] に渡す（クライアント ID は index.html の
/// `google-signin-client_id` メタタグから読まれる）。
Widget buildWebGoogleSignInButton({
  required void Function(String idToken) onIdToken,
}) =>
    _WebGoogleSignInButton(onIdToken: onIdToken);

class _WebGoogleSignInButton extends StatefulWidget {
  const _WebGoogleSignInButton({required this.onIdToken});

  final void Function(String idToken) onIdToken;

  @override
  State<_WebGoogleSignInButton> createState() => _WebGoogleSignInButtonState();
}

class _WebGoogleSignInButtonState extends State<_WebGoogleSignInButton> {
  final _googleSignIn = GoogleSignIn(scopes: const ['email']);
  var _handled = false;

  @override
  void initState() {
    super.initState();
    _googleSignIn.onCurrentUserChanged.listen((account) async {
      if (account == null || _handled) return;
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken != null) {
        _handled = true;
        widget.onIdToken(idToken);
      }
    });
    // 自動サインイン（signInSilently）はしない。
    // ログアウト直後に自動で再ログインしてしまうのを防ぐため、明示クリックのみ。
  }

  @override
  Widget build(BuildContext context) => web.renderButton();
}
