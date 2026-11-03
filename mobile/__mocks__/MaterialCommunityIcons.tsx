import React from 'react';
import { Text } from 'react-native';

export default function MaterialCommunityIcons({ name }: { name: string }) {
  return <Text accessibilityElementsHidden>{name}</Text>;
}
