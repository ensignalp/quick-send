declare module 'react-native-vector-icons/MaterialCommunityIcons' {
  import React from 'react';
  import { TextProps } from 'react-native';

  type IconProps = TextProps & {
    name: string;
    size?: number;
    color?: string;
  };

  const MaterialCommunityIcons: React.ComponentType<IconProps>;
  export default MaterialCommunityIcons;
}
