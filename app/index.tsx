import React, { useState } from 'react';
import { Box } from '@/components/ui/box';
import { Text } from '@/components/ui/text';
import { Button, ButtonText } from '@/components/ui/button';
import {
  Phone,
  PhoneOff,
  ShieldCheck,
  UserCircle,
  Settings,
  ArrowLeft,
  ChevronRight,
} from 'lucide-react-native';
import { Icon } from '@/components/ui/icon';
import { VStack } from '@/components/ui/vstack';
import { HStack } from '@/components/ui/hstack';
import { Pressable } from '@/components/ui/pressable';

const IncomingCallScreen = ({ onDecline }: { onDecline: () => void }) => {
  return (
    <VStack className="flex-1 justify-between items-center bg-background-950 p-6 py-24">
      <VStack className="items-center gap-2">
        <Icon as={UserCircle} className="h-32 w-32 text-typography-400" />
        <Text className="text-4xl font-bold text-white">Unknown Number</Text>
        <Text className="text-xl text-typography-400">+1-234-567-8910</Text>
        <HStack className="items-center gap-2 mt-4 p-2 rounded-md bg-red-900/80 border border-red-700">
          <Icon as={ShieldCheck} className="text-red-400" />
          <Text className="font-bold text-red-400">Suspicious Caller</Text>
        </HStack>
      </VStack>

      <HStack className="w-full justify-around items-center">
        <VStack className="items-center gap-2">
          <Button
            className="bg-red-600 rounded-full h-20 w-20 justify-center items-center"
            onPress={onDecline}
          >
            <Icon as={PhoneOff} size="xl" className="text-white" />
          </Button>
          <Text className="text-white">Decline</Text>
        </VStack>
        <VStack className="items-center gap-2">
          <Button className="bg-green-600 rounded-full h-20 w-20 justify-center items-center">
            <Icon as={Phone} size="xl" className="text-white" />
          </Button>
          <Text className="text-white">Accept</Text>
        </VStack>
      </HStack>
    </VStack>
  );
};

const SettingsScreen = ({ onBack }: { onBack: () => void }) => {
  return (
    <VStack className="flex-1 bg-background-900 p-6 pt-20">
      <HStack className="items-center justify-between pb-8">
        <Pressable onPress={onBack}>
          <Icon as={ArrowLeft} className="text-white" />
        </Pressable>
        <Text className="text-white text-2xl font-bold">Settings</Text>
        <Box className="w-6" />
      </HStack>
      <Pressable>
        <HStack className="justify-between items-center py-4 border-b border-typography-800">
          <Text className="text-white text-lg">Trusted Contacts</Text>
          <Icon as={ChevronRight} className="text-typography-400" />
        </HStack>
      </Pressable>
      <Pressable>
        <HStack className="justify-between items-center py-4 border-b border-typography-800">
          <Text className="text-white text-lg">Notifications</Text>
          <Icon as={ChevronRight} className="text-typography-400" />
        </HStack>
      </Pressable>
    </VStack>
  );
};

export default function Home() {
  const [view, setView] = useState('home'); // 'home', 'incomingCall', 'settings'

  if (view === 'incomingCall') {
    return <IncomingCallScreen onDecline={() => setView('home')} />;
  }

  if (view === 'settings') {
    return <SettingsScreen onBack={() => setView('home')} />;
  }

  return (
    <Box className="flex-1 bg-background-900 justify-center items-center p-6">
      <Pressable
        onPress={() => setView('settings')}
        className="absolute top-20 right-6"
      >
        <Icon as={Settings} className="h-8 w-8 text-typography-400" />
      </Pressable>
      <VStack className="items-center gap-4">
        <Icon as={ShieldCheck} className="h-24 w-24 text-green-400" />
        <Text className="text-white text-3xl font-bold">ElderGuard is Active</Text>
        <Text className="text-typography-400 text-center">
          Your phone line is protected from scam calls and messages.
        </Text>
      </VStack>
      <Button
        onPress={() => setView('incomingCall')}
        className="absolute bottom-24 bg-blue-500"
      >
        <ButtonText>Simulate Incoming Scam Call</ButtonText>
      </Button>
    </Box>
  );
}
