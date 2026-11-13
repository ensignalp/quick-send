module.exports = {
  preset: '@react-native/jest-preset',
  moduleNameMapper: {
    '^@expo/vector-icons/MaterialCommunityIcons$': '<rootDir>/__mocks__/MaterialCommunityIcons.tsx',
    '^@expo-google-fonts/space-grotesk$': '<rootDir>/__mocks__/spaceGrotesk.ts',
  },
};
