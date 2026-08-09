import 'package:equatable/equatable.dart';

class SupportResource extends Equatable {
  const SupportResource({
    required this.id,
    required this.title,
    required this.category,
    required this.url,
  });

  final String id;
  final String title;
  final String category;
  final String url;

  @override
  List<Object?> get props => [id, title, category, url];
}
